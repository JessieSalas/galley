#!/usr/bin/env python3
"""App Store Connect API driver for Galley's release pipeline.

Handles everything scripts/release.sh needs after xcodebuild has already
produced a signed, exported .pkg: upload the build, wait for Apple to finish
processing it, attach it to an existing App Store version, and submit that
version for review via the current (2026) three-step reviewSubmissions flow
(the older one-shot appStoreVersionSubmissions endpoint is retired).

Auth is a single App Store Connect API key (ES256 JWT), the same key
scripts/release.sh already uses for notarization — one credential for the
whole pipeline instead of three.

Deliberately NOT automated: creating the appStoreVersions record and its
"What's New" text for a new version. That's a two-minute dashboard click
that clones the prior version's description/keywords/screenshots — cloning
that through the API is real extra surface for something that isn't the
bottleneck. Create the version in App Store Connect first, then run this.

Usage:
    python3 appstoreconnect.py status --version 1.1.5 \
        --key-id KL448V4YTJ --issuer-id <uuid> --key-path ~/Downloads/AuthKey_KL448V4YTJ.p8

    python3 appstoreconnect.py submit --version 1.1.5 --pkg build/.../Galley.pkg \
        --key-id KL448V4YTJ --issuer-id <uuid> --key-path ~/Downloads/AuthKey_KL448V4YTJ.p8 \
        [--no-submit] [--bundle-id do.thesis.galley] [--poll-seconds 600]
"""
import argparse
import os
import pathlib
import subprocess
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"


def make_token(key_id, issuer_id, key_path):
    with open(key_path) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


class ASC:
    def __init__(self, key_id, issuer_id, key_path):
        self.token = make_token(key_id, issuer_id, key_path)

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"}

    def get(self, path, **params):
        r = requests.get(f"{API}{path}", headers=self._headers(), params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    def post(self, path, body):
        r = requests.post(f"{API}{path}", headers=self._headers(), json=body, timeout=30)
        if not r.ok:
            print(r.text, file=sys.stderr)
        r.raise_for_status()
        return r.json() if r.text else {}

    def patch(self, path, body):
        r = requests.patch(f"{API}{path}", headers=self._headers(), json=body, timeout=30)
        if not r.ok:
            print(r.text, file=sys.stderr)
        r.raise_for_status()
        return r.json() if r.text else {}


def find_app(asc, bundle_id):
    data = asc.get("/apps", **{"filter[bundleId]": bundle_id})["data"]
    if not data:
        sys.exit(f"error: no app found for bundle id {bundle_id}")
    return data[0]["id"]


def find_version(asc, app_id, version):
    data = asc.get(f"/apps/{app_id}/appStoreVersions", **{"filter[versionString]": version})["data"]
    return data[0]["id"] if data else None


def most_recent_version(asc, app_id):
    # `sort` isn't a valid query param on this list endpoint (400s) — fetch
    # and sort client-side instead.
    data = asc.get(f"/apps/{app_id}/appStoreVersions", limit=50)["data"]
    if not data:
        sys.exit("error: no prior App Store version to clone metadata from")
    return max(data, key=lambda v: v["attributes"]["createdDate"])


def create_version(asc, app_id, version, whats_new):
    """Creates a new appStoreVersions entry and clones the most recent
    version's localizations (description/keywords/etc.), so a brand-new
    version doesn't need a manual dashboard visit just to carry forward
    metadata that hasn't changed. Only `whats_new` is genuinely new.

    Apple rejects this (409, ENTITY_ERROR.RELATIONSHIP.INVALID) if a prior
    version is still "open" (e.g. REJECTED, PREPARE_FOR_SUBMISSION) — an app
    can only have one version in flight at a time. Callers should catch
    requests.exceptions.HTTPError and fall back to reuse_version()."""
    source = most_recent_version(asc, app_id)
    print(f"==> No App Store version '{version}' yet — creating one, cloning metadata from {source['attributes']['versionString']}")

    created = asc.post("/appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": source["attributes"]["platform"],
                "versionString": version,
                "copyright": source["attributes"]["copyright"],
                "releaseType": source["attributes"]["releaseType"],
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    version_id = created["data"]["id"]
    clone_localizations(asc, source["id"], version_id, whats_new)
    print(f"==> Created version {version} ({version_id})")
    return version_id


def clone_localizations(asc, source_version_id, dest_version_id, whats_new):
    source_locs = asc.get(f"/appStoreVersions/{source_version_id}/appStoreVersionLocalizations")["data"]
    for loc in source_locs:
        a = loc["attributes"]
        asc.post("/appStoreVersionLocalizations", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {
                    "locale": a["locale"],
                    "description": a["description"],
                    "keywords": a["keywords"],
                    "marketingUrl": a["marketingUrl"],
                    "promotionalText": a["promotionalText"],
                    "supportUrl": a["supportUrl"],
                    "whatsNew": whats_new,
                },
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": dest_version_id}}},
            }
        })
    print(f"==> Cloned {len(source_locs)} localization(s)")


def reuse_version(asc, source, version, whats_new):
    """A prior version (e.g. REJECTED) is still open, so Apple won't let a
    new one be created alongside it — the normal post-rejection flow is to
    edit that version in place (version string included) and resubmit, not
    create a sibling. Only PATCHes versionString here — whatsNew is rejected
    by the API ("cannot be edited at this time") until a build is attached,
    so the caller sets it later via set_whats_new()."""
    version_id = source["id"]
    old_version_string = source["attributes"]["versionString"]
    print(f"==> Version {old_version_string} ({source['attributes']['appStoreState']}) is still open — updating it to {version} in place instead of creating a new one")

    asc.patch(f"/appStoreVersions/{version_id}", {
        "data": {
            "type": "appStoreVersions",
            "id": version_id,
            "attributes": {"versionString": version},
        }
    })
    print(f"==> Renamed to version {version} ({version_id})")
    return version_id


def set_whats_new(asc, version_id, whats_new):
    if not whats_new:
        return
    locs = asc.get(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    for loc in locs:
        try:
            asc.patch(f"/appStoreVersionLocalizations/{loc['id']}", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": {"whatsNew": whats_new},
                }
            })
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code == 409:
                # Apple rejects whatsNew on an app's first-ever version —
                # there's nothing prior to describe a change from. Not
                # fatal: everything else about the submission still stands.
                print("==> Skipping 'What's New' — not editable yet (likely this app's first real version)")
                return
            raise
    print(f"==> Set 'What's New' on {len(locs)} localization(s)")


def set_review_notes(asc, version_id, notes):
    """Write App Review Information -> Notes.

    Worth the extra call: 1.1.5 was rejected twice under Guideline 4 for a
    Window-menu item that was present and working both times. When a fix is
    a reviewer-discoverability fix, saying where to look is the fix.
    """
    if not notes:
        return
    detail = asc.get(f"/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    if detail:
        asc.patch(f"/appStoreReviewDetails/{detail['id']}", {
            "data": {
                "type": "appStoreReviewDetails",
                "id": detail["id"],
                "attributes": {"notes": notes},
            }
        })
    else:
        asc.post("/appStoreReviewDetails", {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": {"notes": notes},
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    }
                },
            }
        })
    print("==> Set App Review notes")


def find_or_create_version(asc, app_id, version, whats_new):
    existing = find_version(asc, app_id, version)
    if existing:
        return existing, False
    if not whats_new:
        sys.exit(
            f"error: no App Store version '{version}' exists yet, and --whats-new wasn't given "
            f"to auto-create one. Either pass --whats-new \"...\", or create the version by hand "
            f"in App Store Connect first."
        )
    try:
        return create_version(asc, app_id, version, whats_new), True
    except requests.exceptions.HTTPError as e:
        # Apple refuses to create a second version while one is still open,
        # but is inconsistent about which code it uses: 409 when the open
        # version is PREPARE_FOR_SUBMISSION, 403 when it is REJECTED. Both
        # mean the same thing, and the fix for both is the documented
        # post-rejection flow — edit the open version in place. If this is
        # really a permissions problem, the PATCH below fails loudly too.
        if e.response is None or e.response.status_code not in (403, 409):
            raise
        return reuse_version(asc, most_recent_version(asc, app_id), version, whats_new), False


def upload_build(pkg_path, key_id, issuer_id, key_path):
    # Current altool (verified against this machine's Xcode) takes no
    # bundle-id/version/type flags for --upload-package at all — the .pkg
    # already carries that metadata — and uses --api-key/--api-issuer, not
    # the older --apiKey/--apiIssuer. It also only looks for the .p8 file in
    # a few fixed locations (or $API_PRIVATE_KEYS_DIR), not an arbitrary path.
    print(f"==> Uploading {pkg_path} via altool")
    env = {**os.environ, "API_PRIVATE_KEYS_DIR": str(pathlib.Path(key_path).parent)}
    cmd = [
        "xcrun", "altool", "--upload-package", pkg_path,
        "--api-key", key_id,
        "--api-issuer", issuer_id,
        "--wait",
    ]
    subprocess.run(cmd, check=True, env=env)


def wait_for_build(asc, app_id, build_number, poll_seconds):
    print(f"==> Waiting for build {build_number} to finish processing (up to {poll_seconds}s)")
    deadline = time.time() + poll_seconds
    while time.time() < deadline:
        # Top-level /builds, not the nested /apps/{id}/builds route — the
        # latter 400s on filter[version] ("parameter not allowed").
        data = asc.get("/builds", **{"filter[app]": app_id, "filter[version]": build_number})["data"]
        if data:
            state = data[0]["attributes"]["processingState"]
            print(f"    processingState={state}")
            if state == "VALID":
                return data[0]["id"]
            if state == "INVALID" or state == "FAILED":
                sys.exit(f"error: build {build_number} failed processing ({state})")
        time.sleep(20)
    sys.exit(f"error: timed out waiting for build {build_number} to process")


def attach_build(asc, version_id, build_id):
    print(f"==> Attaching build {build_id} to version {version_id}")
    asc.patch(f"/appStoreVersions/{version_id}", {
        "data": {
            "type": "appStoreVersions",
            "id": version_id,
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    })


def existing_open_submission(asc, app_id):
    # A submission whose state is UNRESOLVED_ISSUES (i.e. a prior rejection)
    # LOOKS unsubmitted (submitted=false) but is actually terminal: its
    # rejected item can't be deleted via this API ("Item was already
    # submitted") and no new item can be added to the submission itself
    # ("state does not allow adding more items"). Only a genuinely fresh,
    # empty READY_FOR_REVIEW submission is safe to reuse.
    data = asc.get("/reviewSubmissions", **{"filter[app]": app_id}).get("data", [])
    for s in data:
        if not s["attributes"].get("submitted") and s["attributes"].get("state") == "READY_FOR_REVIEW":
            return s["id"]
    return None


def submit_for_review(asc, app_id, version_id):
    submission_id = existing_open_submission(asc, app_id)
    if submission_id:
        print(f"==> Reusing existing unsubmitted review submission {submission_id}")
    else:
        print("==> Creating review submission")
        resp = asc.post("/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        submission_id = resp["data"]["id"]

    print("==> Adding version to submission")
    try:
        asc.post("/reviewSubmissionItems", {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        })
    except requests.exceptions.HTTPError as e:
        if e.response is not None and e.response.status_code == 409:
            sys.exit(
                "error: this version is still linked to an earlier rejected review submission, and the "
                "App Store Connect API has no way to detach it (the dashboard's own 'remove rejected "
                "items' action isn't exposed via the API). Finish this one manually: App Store Connect "
                "-> this app -> App Review Issues & Messages -> remove the rejected item (or Edit -> "
                "Add for Review -> Resubmit to App Review). The build is already uploaded and attached; "
                "this is just the last click."
            )
        raise

    print("==> Submitting for review")
    asc.patch(f"/reviewSubmissions/{submission_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"submitted": True},
        }
    })
    print(f"==> Submitted. Track status: https://appstoreconnect.apple.com/apps/{app_id}/appstore")


def cmd_status(args):
    asc = ASC(args.key_id, args.issuer_id, args.key_path)
    app_id = find_app(asc, args.bundle_id)
    print(f"app id: {app_id}")
    for v in asc.get(f"/apps/{app_id}/appStoreVersions", limit=10)["data"]:
        a = v["attributes"]
        print(f"  version {a['versionString']}: {a['appStoreState']} ({v['id']})")
    for b in asc.get(f"/apps/{app_id}/builds", limit=10)["data"]:
        a = b["attributes"]
        print(f"  build {a['version']}: {a['processingState']} uploaded {a.get('uploadedDate')}")


def cmd_submit(args):
    asc = ASC(args.key_id, args.issuer_id, args.key_path)
    app_id = find_app(asc, args.bundle_id)
    version_id, whats_new_set = find_or_create_version(asc, app_id, args.version, args.whats_new)

    upload_build(args.pkg, args.key_id, args.issuer_id, args.key_path)
    build_id = wait_for_build(asc, app_id, args.build_number, args.poll_seconds)
    attach_build(asc, version_id, build_id)
    if not whats_new_set:
        set_whats_new(asc, version_id, args.whats_new)
    set_review_notes(asc, version_id, args.review_notes)

    if args.no_submit:
        print("==> --no-submit set: build attached, stopping before review submission.")
        print(f"    Submit manually at https://appstoreconnect.apple.com/apps/{app_id}/appstore")
        return

    submit_for_review(asc, app_id, version_id)


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--key-id", required=True)
    common.add_argument("--issuer-id", required=True)
    common.add_argument("--key-path", required=True)
    common.add_argument("--bundle-id", default="do.thesis.galley")

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_status = sub.add_parser("status", parents=[common], help="Print current app/version/build state (read-only)")
    p_status.set_defaults(func=cmd_status)

    p_submit = sub.add_parser("submit", parents=[common], help="Upload, attach, and submit a build for review")
    p_submit.add_argument("--version", required=True, help="Marketing version, e.g. 1.1.5")
    p_submit.add_argument("--review-notes", default="",
                          help="App Review Information -> Notes; use it to point the reviewer "
                               "straight at whatever a previous rejection said was missing")
    p_submit.add_argument("--pkg", required=True, help="Path to the exported .pkg")
    p_submit.add_argument("--build-number", help="CFBundleVersion; read from project.yml if omitted")
    p_submit.add_argument("--poll-seconds", type=int, default=1800)
    p_submit.add_argument("--no-submit", action="store_true",
                           help="Upload and attach the build, but don't submit for review")
    p_submit.add_argument("--whats-new",
                           help="'What's New' text. Required only if --version doesn't exist yet "
                                "in App Store Connect — if so, this script creates it, cloning "
                                "description/keywords/etc. from the most recent existing version.")
    p_submit.set_defaults(func=cmd_submit)

    args = parser.parse_args()

    if args.command == "submit" and not args.build_number:
        import re
        with open("project.yml") as f:
            m = re.search(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', f.read())
        if not m:
            sys.exit("error: --build-number not given and couldn't read it from project.yml")
        args.build_number = m.group(1)

    args.func(args)


if __name__ == "__main__":
    main()
