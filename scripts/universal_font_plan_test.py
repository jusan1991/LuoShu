#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def target_slot(
    name: str,
    families: list[str],
    *,
    weight: int = 400,
    han: bool = False,
    latin: bool = True,
    digits: bool = True,
    variable: bool = False,
) -> dict:
    return {
        "slotName": name,
        "partition": "system",
        "families": families,
        "metrics": {
            "weightClass": weight,
            "coverage": {
                "hasHan": han,
                "hanCount": 7000 if han else 0,
                "hasLatin": latin,
                "latinCount": 52 if latin else 0,
                "hasDigits": digits,
                "digitCount": 10 if digits else 0,
            },
            "variationAxes": (
                [{"tag": "wght", "min": 100, "default": 400, "max": 900}]
                if variable else []
            ),
        },
        "xmlRefs": [
            {
                "sourceXml": "/system/etc/fonts.xml",
                "family": families[0] if families else "",
                "familyAttributes": {},
                "weight": weight,
                "style": "normal",
                "resolvedPath": "/system/fonts/" + name,
            }
        ],
        "runtimeEvidence": {"fontManager": True, "mount": False},
        "legacyReplaceable": True,
    }


def role(role_name: str, action: str, confidence: int = 100) -> dict:
    return {
        "role": role_name,
        "action": action,
        "confidence": confidence,
        "reasons": ["synthetic-test"],
        "currentReplaceable": True,
        "comparison": "agree",
        "evidence": {},
    }


def face(
    uid: str,
    file_uid: str,
    *,
    family: str,
    weight: int,
    cjk: bool,
    latin: bool = True,
    numeric: bool = True,
    variable: bool = False,
    italic: bool = False,
) -> dict:
    return {
        "uid": uid,
        "fileUid": file_uid,
        "fileName": uid.replace(":", "-") + ".ttf",
        "faceIndex": 0,
        "names": {
            "family": family,
            "familyNormalized": family.lower().replace(" ", "-"),
            "subfamily": "Italic" if italic else ("Bold" if weight >= 700 else "Regular"),
            "fullName": family,
            "postScriptName": uid.replace(":", "-"),
        },
        "format": "TTF/glyf",
        "style": {
            "weight": weight,
            "widthClass": 5,
            "italic": italic,
            "fixedPitch": False,
        },
        "metrics": {
            "unitsPerEm": 1000,
            "head": {"yMin": -250, "yMax": 1000},
            "hhea": {"ascent": 900, "descent": -250, "lineGap": 0},
            "os2": {
                "weightClass": weight,
                "widthClass": 5,
                "typoAscender": 850,
                "typoDescender": -200,
                "typoLineGap": 0,
                "winAscent": 1000,
                "winDescent": 250,
                "capHeight": 700,
                "xHeight": 500,
            },
        },
        "variation": {
            "variable": variable,
            "axes": (
                [{"tag": "wght", "name": "Weight", "min": 100.0, "default": 400.0, "max": 900.0}]
                if variable else []
            ),
            "namedInstances": [],
        },
        "tables": {
            "all": ["cmap", "head", "hhea", "maxp", "name", "OS/2"] + (["fvar"] if variable else []),
            "outline": "glyf",
            "color": [],
            "variable": ["fvar"] if variable else [],
            "shaping": ["GSUB", "GPOS"],
        },
        "coverage": {
            "codepoints": 10000 if cjk else 300,
            "coreHan": 7000 if cjk else 0,
            "minimumCoreHan": 6000,
            "scriptCounts": {"han": 7000 if cjk else 0, "latin": 100},
            "emojiCodepointsApprox": 0,
            "probes": {
                "cjk": {"hits": 160 if cjk else 0, "total": 160, "ratio": 1.0 if cjk else 0.0},
                "latin": {"hits": 52 if latin else 0, "total": 52, "ratio": 1.0 if latin else 0.0},
                "digits": {"hits": 10 if numeric else 0, "total": 10, "ratio": 1.0 if numeric else 0.0},
                "punctuation": {"hits": 16, "total": 16, "ratio": 1.0},
            },
        },
        "capabilities": {
            "text": True,
            "latinUi": latin,
            "cjkUi": cjk,
            "numeric": numeric,
            "punctuationUi": True,
            "monospaceCandidate": False,
            "variable": variable,
            "variableWeight": variable,
            "variableWidth": False,
            "variableOpticalSize": False,
            "colorFont": False,
            "globalUiCandidate": cjk,
        },
        "warnings": [],
    }


def source_profile(*, include_cjk: bool = True) -> dict:
    files = []
    if include_cjk:
        files.append(
            {
                "fileUid": "sha256:cjk-file",
                "sha256": "cjk-file",
                "sourcePath": "/sdcard/LuoShu/fonts/DemoCJK-VF.ttf",
                "fileName": "DemoCJK-VF.ttf",
                "bytes": 100000,
                "container": "TTF",
                "collection": False,
                "requiresSfntConversion": False,
                "faceCount": 1,
                "faces": [
                    face(
                        "sha256:cjk-file:face:0",
                        "sha256:cjk-file",
                        family="Demo CJK",
                        weight=400,
                        cjk=True,
                        variable=True,
                    )
                ],
            }
        )
    files.append(
        {
            "fileUid": "sha256:latin-bold",
            "sha256": "latin-bold",
            "sourcePath": "/sdcard/LuoShu/fonts/DemoLatin-Bold.ttf",
            "fileName": "DemoLatin-Bold.ttf",
            "bytes": 50000,
            "container": "TTF",
            "collection": False,
            "requiresSfntConversion": False,
            "faceCount": 1,
            "faces": [
                face(
                    "sha256:latin-bold:face:0",
                    "sha256:latin-bold",
                    family="Demo Latin",
                    weight=700,
                    cjk=False,
                    variable=False,
                )
            ],
        }
    )
    profile_id = "sha256:" + ("with-cjk" if include_cjk else "latin-only")
    return {
        "schema": "source-font-profile-v1",
        "profileRevision": 1,
        "state": "ready",
        "generatedAt": 1,
        "profileId": profile_id,
        "summary": {
            "fileCount": len(files),
            "faceCount": len(files),
            "familyCount": len(files),
            "containers": ["TTF"],
            "weights": [400, 700] if include_cjk else [700],
            "axisTags": ["wght"] if include_cjk else [],
            "requiresSfntConversion": False,
            "capabilities": {
                "latinUi": True,
                "cjkUi": include_cjk,
                "numeric": True,
                "monospaceCandidate": False,
                "variable": include_cjk,
                "variableWeight": include_cjk,
                "colorFont": False,
                "globalUiCandidate": include_cjk,
            },
        },
        "families": {},
        "files": files,
    }


def fixture() -> tuple[dict, dict]:
    slots = {
        "/system/fonts/UiCjk.ttf": target_slot(
            "UiCjk.ttf", ["sans-serif"], han=True, weight=400
        ),
        "/system/fonts/UiLatin-Bold.ttf": target_slot(
            "UiLatin-Bold.ttf", ["sans-serif"], han=False, weight=700
        ),
        "/product/fonts/CjkFallback.otf": target_slot(
            "CjkFallback.otf", ["zh-Hans"], han=True, weight=400
        ),
        "/system_ext/fonts/Digits.ttf": target_slot(
            "Digits.ttf", ["numeric-ui"], han=False, weight=400
        ),
        "/system/fonts/AndroidClock.ttf": target_slot(
            "AndroidClock.ttf", ["clock-ui"], han=False, weight=400
        ),
        "/system/fonts/VariableLatin.ttf": target_slot(
            "VariableLatin.ttf", ["sans-serif"], han=False, weight=500, variable=True
        ),
        "/system/fonts/RobotoMono.ttf": target_slot(
            "RobotoMono.ttf", ["monospace"], han=False, weight=400
        ),
        "/system/fonts/NotoColorEmoji.ttf": target_slot(
            "NotoColorEmoji.ttf", ["emoji"], han=False, latin=False, digits=False
        ),
        "/vendor/fonts/Mystery.ttf": target_slot(
            "Mystery.ttf", [], han=True, weight=400
        ),
    }
    roles = {
        "/system/fonts/UiCjk.ttf": role("ui-sans", "replace"),
        "/system/fonts/UiLatin-Bold.ttf": role("latin", "conditional"),
        "/product/fonts/CjkFallback.otf": role("cjk", "conditional"),
        "/system_ext/fonts/Digits.ttf": role("numeric", "specialized"),
        "/system/fonts/AndroidClock.ttf": role("clock", "specialized"),
        "/system/fonts/VariableLatin.ttf": role("latin", "conditional"),
        "/system/fonts/RobotoMono.ttf": role("monospace", "preserve"),
        "/system/fonts/NotoColorEmoji.ttf": role("emoji", "preserve"),
        "/vendor/fonts/Mystery.ttf": role("unknown-protected", "review", 45),
    }
    topology = {
        "schema": "device-font-topology-v1",
        "topologyRevision": 2,
        "state": "ready",
        "generatedAt": 1,
        "buildKey": "universal-plan-test",
        "romKind": "generic",
        "summary": {"slotCount": len(slots)},
        "slots": slots,
        "families": {},
        "runtime": {},
    }
    role_map = {
        "schema": "device-font-roles-v1",
        "roleRevision": 1,
        "state": "ready",
        "generatedAt": 1,
        "buildKey": "universal-plan-test",
        "romKind": "generic",
        "summary": {"slotCount": len(roles)},
        "slots": roles,
    }
    return topology, role_map


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    planner = root / "common/universal_font_plan.py"

    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        topology_data, roles_data = fixture()
        profile_data = source_profile(include_cjk=True)

        topology = temp / "topology.json"
        roles = temp / "roles.json"
        profile = temp / "profile.json"
        output = temp / "plan.json"
        topology.write_text(json.dumps(topology_data), encoding="utf-8")
        roles.write_text(json.dumps(roles_data), encoding="utf-8")
        profile.write_text(json.dumps(profile_data), encoding="utf-8")

        command = [
            sys.executable,
            str(planner),
            "--topology", str(topology),
            "--roles", str(roles),
            "--source-profile", str(profile),
            "--output", str(output),
        ]
        first = run(command)
        assert first.returncode == 0, first.stderr or first.stdout
        plan = json.loads(output.read_text(encoding="utf-8"))
        assert plan["schema"] == "universal-font-plan-v1"
        assert plan["state"] == "planned"
        assert plan["mutatesSystem"] is False
        assert plan["summary"]["executableNow"] is False

        ui_cjk = plan["targets"]["/system/fonts/UiCjk.ttf"]
        assert ui_cjk["action"] == "compile"
        assert ui_cjk["source"]["uid"] == "sha256:cjk-file:face:0"
        assert "metrics-normalization" in ui_cjk["requirements"]
        assert "variable-instance" in ui_cjk["requirements"]

        latin_bold = plan["targets"]["/system/fonts/UiLatin-Bold.ttf"]
        assert latin_bold["action"] == "compile"
        # Exact static 700 must beat a variable face that could also synthesize 700.
        assert latin_bold["source"]["uid"] == "sha256:latin-bold:face:0"
        assert latin_bold["selection"]["weightMode"] == "static"
        assert latin_bold["selection"]["weightDistance"] == 0.0
        assert "static-weight-fallback" not in latin_bold["risks"]

        cjk = plan["targets"]["/product/fonts/CjkFallback.otf"]
        assert cjk["source"]["uid"] == "sha256:cjk-file:face:0"
        assert cjk["action"] == "compile"

        numeric = plan["targets"]["/system_ext/fonts/Digits.ttf"]
        assert numeric["action"] == "compile-specialized"
        assert numeric["compiler"] == "specialized"
        assert "specialized-numeric-contract" in numeric["requirements"]

        clock = plan["targets"]["/system/fonts/AndroidClock.ttf"]
        assert clock["action"] == "compile-specialized"
        assert "stock-exact-advance" in clock["requirements"]

        variable_target = plan["targets"]["/system/fonts/VariableLatin.ttf"]
        assert variable_target["source"]["uid"] == "sha256:cjk-file:face:0"
        assert variable_target["source"]["variable"] is True
        assert "variable-instance" not in variable_target["requirements"]

        mono = plan["targets"]["/system/fonts/RobotoMono.ttf"]
        assert mono["action"] == "preserve"
        assert "source" not in mono

        emoji = plan["targets"]["/system/fonts/NotoColorEmoji.ttf"]
        assert emoji["action"] == "preserve"

        mystery = plan["targets"]["/vendor/fonts/Mystery.ttf"]
        assert mystery["action"] == "review"
        assert mystery["status"] == "review"

        plan_id = plan["planId"]
        second = run(command)
        assert second.returncode == 0, second.stderr or second.stdout
        plan2 = json.loads(output.read_text(encoding="utf-8"))
        assert plan2["planId"] == plan_id, "planId must be deterministic"

        validated = run([
            sys.executable, str(planner),
            "--topology", str(topology),
            "--roles", str(roles),
            "--source-profile", str(profile),
            "--validate", str(output),
        ])
        assert validated.returncode == 0, validated.stderr or validated.stdout

        # A Latin-only source must block CJK/UI-CJK instead of silently falling
        # back to a Latin face, while leaving protected slots untouched.
        latin_profile = temp / "latin-only.json"
        latin_plan_path = temp / "latin-only-plan.json"
        latin_profile.write_text(json.dumps(source_profile(include_cjk=False)), encoding="utf-8")
        blocked = run([
            sys.executable, str(planner),
            "--topology", str(topology),
            "--roles", str(roles),
            "--source-profile", str(latin_profile),
            "--output", str(latin_plan_path),
        ])
        assert blocked.returncode == 0, blocked.stderr or blocked.stdout
        latin_plan = json.loads(latin_plan_path.read_text(encoding="utf-8"))
        assert latin_plan["targets"]["/system/fonts/UiCjk.ttf"]["action"] == "blocked"
        assert latin_plan["targets"]["/product/fonts/CjkFallback.otf"]["action"] == "blocked"
        assert latin_plan["targets"]["/system/fonts/RobotoMono.ttf"]["action"] == "preserve"

        # Cross-device role data must never be accepted.
        bad_roles = dict(roles_data)
        bad_roles["buildKey"] = "different-build"
        bad_roles_path = temp / "bad-roles.json"
        bad_roles_path.write_text(json.dumps(bad_roles), encoding="utf-8")
        mismatch = run([
            sys.executable, str(planner),
            "--topology", str(topology),
            "--roles", str(bad_roles_path),
            "--source-profile", str(profile),
        ])
        assert mismatch.returncode != 0
        assert "buildKey" in (mismatch.stdout + mismatch.stderr)

    print("universal_font_plan_test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
