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


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    script = root / "common/font_topology_snapshot.py"

    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        inventory = temp / "device_font_inventory.json"
        output = temp / "device_font_topology.json"
        dump = temp / "font-manager.txt"
        mountinfo = temp / "mountinfo.txt"
        data_config = temp / "config.xml"
        data_dir = temp / "data-fonts"
        data_dir.mkdir()

        inventory.write_text(
            json.dumps(
                {
                    "schema": "device-font-inventory-v1",
                    "inventoryRevision": 1,
                    "scannerRevision": 4,
                    "state": "ready",
                    "buildKey": "topology-test-build",
                    "romKind": "hyperos",
                    "xmlSources": [
                        "/system/etc/fonts.xml",
                        "/product/etc/fonts_customization.xml",
                    ],
                    "families": {
                        "sans-serif": ["/system/fonts/Roboto-Regular.ttf"],
                        "sans-serif-condensed": ["/product/fonts/UiCondensed.ttf"],
                    },
                    "slots": {
                        "/system/fonts/Roboto-Regular.ttf": {
                            "partition": "system",
                            "slotName": "Roboto-Regular.ttf",
                            "source": "xml",
                            "sourceXmls": ["/system/etc/fonts.xml"],
                            "metrics": {"unitsPerEm": 2048},
                        },
                        "/product/fonts/UiCondensed.ttf": {
                            "partition": "product",
                            "slotName": "UiCondensed.ttf",
                            "source": "xml",
                            "sourceXmls": ["/product/etc/fonts_customization.xml"],
                        },
                        "/system_ext/fonts/OemUi-Regular.ttf": {
                            "partition": "system_ext",
                            "slotName": "OemUi-Regular.ttf",
                            "source": "verified-scan",
                        },
                    },
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        dump.write_text(
            """
FontManagerService:
  family=sans-serif
  font=/system/fonts/Roboto-Regular.ttf
  updated=/data/fonts/files/updated.ttf
""".strip()
            + "\n",
            encoding="utf-8",
        )
        mountinfo.write_text(
            "1 2 0:1 / /system/fonts/Roboto-Regular.ttf ro - bind /system/fonts/Roboto-Regular.ttf ro\n",
            encoding="utf-8",
        )
        data_config.write_text(
            '<fontConfig configVersion="12"><font postScriptName="UpdatedSans" file="/data/fonts/files/updated.ttf"/></fontConfig>\n',
            encoding="utf-8",
        )
        (data_dir / "updated.ttf").write_bytes(b"test-font-bytes")

        built = run(
            [
                sys.executable,
                str(script),
                "--inventory",
                str(inventory),
                "--output",
                str(output),
                "--font-manager-dump",
                str(dump),
                "--data-fonts-config",
                str(data_config),
                "--data-fonts-dir",
                str(data_dir),
                "--mountinfo",
                str(mountinfo),
            ]
        )
        assert built.returncode == 0, built.stderr or built.stdout
        result = json.loads(built.stdout)
        payload = json.loads(output.read_text(encoding="utf-8"))

        assert result["status"] == "ok"
        assert payload["schema"] == "device-font-topology-v1"
        assert payload["topologyRevision"] == 1
        assert payload["state"] == "ready"
        assert payload["buildKey"] == "topology-test-build"
        assert payload["romKind"] == "hyperos"
        assert payload["summary"]["slotCount"] == 3
        assert payload["summary"]["familyCount"] == 2
        assert payload["summary"]["edgeCount"] == 2
        assert payload["summary"]["partitionCount"] == 3
        assert payload["summary"]["xmlSourceCount"] == 2
        assert payload["summary"]["runtimeConfirmedSlotCount"] == 1
        assert payload["summary"]["runtimeConfirmedFamilyCount"] == 1
        assert payload["summary"]["dataFontFileCount"] == 1
        assert payload["summary"]["dataFontConfigReferenceCount"] == 1
        assert payload["partitions"] == ["product", "system", "system_ext"]

        roboto = payload["slots"]["/system/fonts/Roboto-Regular.ttf"]
        assert roboto["families"] == ["sans-serif"]
        assert roboto["runtimeEvidence"]["fontManager"] is True
        assert roboto["runtimeEvidence"]["mount"] is True
        assert roboto["metrics"]["unitsPerEm"] == 2048

        oem = payload["slots"]["/system_ext/fonts/OemUi-Regular.ttf"]
        assert oem["families"] == []
        assert oem["runtimeEvidence"]["fontManager"] is False

        assert payload["families"]["sans-serif"]["runtimeConfirmed"] is True
        assert payload["families"]["sans-serif-condensed"]["runtimeConfirmed"] is False
        assert payload["runtime"]["fontManager"]["reportedDataFontPaths"] == [
            "/data/fonts/files/updated.ttf"
        ]
        assert payload["runtime"]["dataFontsConfig"]["version"] == "12"
        assert payload["runtime"]["dataFontsConfig"]["fontReferences"] == [
            "/data/fonts/files/updated.ttf"
        ]
        assert payload["runtime"]["dataFontsConfig"]["namedReferences"] == [
            "UpdatedSans"
        ]
        assert payload["runtime"]["dataFontFiles"][0]["fileName"] == "updated.ttf"

        validated = run(
            [
                sys.executable,
                str(script),
                "--validate",
                "--inventory",
                str(inventory),
                "--output",
                str(output),
            ]
        )
        assert validated.returncode == 0, validated.stderr or validated.stdout
        assert json.loads(validated.stdout)["status"] == "ok"

        changed = json.loads(inventory.read_text(encoding="utf-8"))
        changed["buildKey"] = "different-build"
        inventory.write_text(json.dumps(changed), encoding="utf-8")
        stale = run(
            [
                sys.executable,
                str(script),
                "--validate",
                "--inventory",
                str(inventory),
                "--output",
                str(output),
            ]
        )
        assert stale.returncode != 0
        assert "不匹配" in json.loads(stale.stdout)["message"]

    print("font_topology_snapshot_test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
