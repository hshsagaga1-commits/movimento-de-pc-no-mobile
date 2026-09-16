#!/usr/bin/env python3
"""Reconstruct the closed V614 R2 experiment without changing its runtime.

Usage:
  python3 V614_CAUSAL_GEOMETRY_AUDIT.py "/path/to/V614 report.md"

The parser uses only fields already emitted by V614.  In particular, each
accepted frame records the screen projection before and after Controller.Update.
For every matched segment this gives the exact identity:

    endpoint displacement = sum(within-update displacement)
                          + sum(inter-frame boundary displacement)

The second term includes Head-relative rig/pose evolution between camera
updates; it is not labeled animation because the report did not record joints
or animation tracks.
"""

from __future__ import annotations

import json
import hashlib
import math
import re
import statistics
import sys
from pathlib import Path


NUM = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def f(pattern: str, text: str) -> float:
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"missing {pattern!r}")
    return float(match.group(1))


def i(pattern: str, text: str) -> int:
    return int(f(pattern, text))


def vec(pattern: str, text: str) -> tuple[float, float, float]:
    match = re.search(pattern + rf"({NUM}),\s*({NUM}),\s*({NUM})", text)
    if not match:
        raise ValueError(f"missing vector {pattern!r}")
    return tuple(float(match.group(index)) for index in range(1, 4))


def pair_vec(key: str, text: str):
    match = re.search(
        rf"{re.escape(key)}=({NUM}),\s*({NUM}),\s*({NUM})->({NUM}),\s*({NUM}),\s*({NUM})",
        text,
    )
    if not match:
        raise ValueError(f"missing vector pair {key}")
    values = [float(match.group(index)) for index in range(1, 7)]
    return tuple(values[:3]), tuple(values[3:])


def screen_segment(key: str, text: str):
    match = re.search(
        rf"{re.escape(key)}=\{{start=({NUM}),\s*({NUM}),\s*({NUM})\s+"
        rf"end=({NUM}),\s*({NUM}),\s*({NUM})\s+dx=({NUM})\s+dy=({NUM})",
        text,
    )
    if not match:
        raise ValueError(f"missing segment screen block {key}")
    values = [float(match.group(index)) for index in range(1, 9)]
    return {"before": tuple(values[:3]), "after": tuple(values[3:6]), "dx": values[6], "dy": values[7]}


def screen_frame(key: str, text: str):
    match = re.search(
        rf"{re.escape(key)}=({NUM}),\s*({NUM}),\s*({NUM})->({NUM}),\s*({NUM}),\s*({NUM})",
        text,
    )
    if not match:
        raise ValueError(f"missing frame screen block {key}")
    values = [float(match.group(index)) for index in range(1, 7)]
    return {"before": tuple(values[:3]), "after": tuple(values[3:])}


def norm(value):
    return math.sqrt(sum(component * component for component in value))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def wrap_degrees(value: float) -> float:
    return (value + 180.0) % 360.0 - 180.0


def mean(values):
    return statistics.fmean(values) if values else float("nan")


def median(values):
    return statistics.median(values) if values else float("nan")


def pearson(xs, ys):
    if len(xs) < 3 or len(xs) != len(ys):
        return float("nan")
    mx, my = mean(xs), mean(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
    return numerator / denominator if denominator else float("nan")


def parse_report(path: Path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    samples = {}
    segments = {}
    pairs = []
    section = None
    for raw in lines:
        line = raw.strip()
        if line.startswith("=== V614 ACCEPTED PER-FRAME SAMPLE DATA"):
            section = "frames"
            continue
        if line.startswith("=== V614 ELIGIBLE NON-OVERLAPPING SEGMENTS"):
            section = "segments"
            continue
        if line.startswith("=== V614 MATCHED SEGMENT PAIRS"):
            section = "pairs"
            continue
        if line.startswith("==="):
            section = None
            continue
        if section == "frames" and line.startswith("frame="):
            frame = i(r"frame=(\d+)", line)
            samples[frame] = {
                "frame": frame,
                "phase": re.search(r"phase=(\w+)", line).group(1),
                "window": re.search(r"window=(\w+)", line).group(1),
                "time": f(rf"time=({NUM})", line),
                "dt": f(rf"dt=({NUM})", line),
                "yaw": f(rf"yawSigned=({NUM})", line),
                "pitch": f(rf"pitchSigned=({NUM})", line),
                "camera_yaw_before": f(rf"cameraYaw=({NUM})->", line),
                "camera_yaw_after": f(rf"cameraYaw={NUM}->({NUM})", line),
                "camera_pitch_before": f(rf"cameraPitch=({NUM})->", line),
                "camera_pitch_after": f(rf"cameraPitch={NUM}->({NUM})", line),
                "subject_to_head": vec(r"subjectToHead=", line),
                "primary_to_head": vec(r"primaryToHead=", line),
                "primary": screen_frame("primaryScreen", line),
                "head": screen_frame("headScreen", line),
                "subject": screen_frame("subjectScreen", line),
            }
        elif section == "segments" and line.startswith("id="):
            segment_id = re.search(r"id=([^\s]+)", line).group(1)
            frame_match = re.search(r"frameRange=(\d+)-(\d+)", line)
            camera_yaw = re.search(rf"cameraYaw=({NUM})->({NUM})", line)
            camera_pitch = re.search(rf"cameraPitch=({NUM})->({NUM})", line)
            segments[segment_id] = {
                "id": segment_id,
                "route": re.search(r"route=(\w+)", line).group(1),
                "window": re.search(r"window=(\w+)", line).group(1),
                "frames": i(r"frames=(\d+)", line),
                "frame_start": int(frame_match.group(1)),
                "frame_end": int(frame_match.group(2)),
                "duration": f(rf"duration=({NUM})", line),
                "signed_yaw": f(rf"totalSignedYaw=({NUM})", line),
                "abs_yaw": f(rf"totalAbsYaw=({NUM})", line),
                "net_pitch": f(rf"netPitch=({NUM})", line),
                "abs_pitch": f(rf"totalAbsPitch=({NUM})", line),
                "primary": screen_segment("primary", line),
                "head": screen_segment("head", line),
                "subject": screen_segment("subject", line),
                "subject_to_primary": pair_vec("subjectToPrimary", line),
                "subject_to_head": pair_vec("subjectToHead", line),
                "primary_to_head": pair_vec("primaryToHead", line),
                "camera_yaw": (float(camera_yaw.group(1)), float(camera_yaw.group(2))),
                "camera_pitch": (float(camera_pitch.group(1)), float(camera_pitch.group(2))),
            }
        elif section == "pairs" and line.startswith("pair="):
            match = re.search(r"pair=(\d+)\s+touch=([^\(]+)\([^\)]+\)\s+relay=([^\(]+)\([^\)]+\)", line)
            pairs.append({"pair": int(match.group(1)), "touch": match.group(2), "relay": match.group(3)})
    return text, lines, samples, segments, pairs


def decompose(segment, samples):
    frames = [samples[frame] for frame in range(segment["frame_start"], segment["frame_end"] + 1) if frame in samples]
    if len(frames) != segment["frames"]:
        raise ValueError(f"{segment['id']}: expected {segment['frames']} frames, found {len(frames)}")

    result = {}
    for point in ("head", "primary", "subject"):
        within = sum(frame[point]["after"][0] - frame[point]["before"][0] for frame in frames)
        boundary = sum(frames[index + 1][point]["before"][0] - frames[index][point]["after"][0]
                       for index in range(len(frames) - 1))
        endpoint = frames[-1][point]["after"][0] - frames[0][point]["before"][0]
        result[point] = {"within_x": within, "boundary_x": boundary, "endpoint_x": endpoint,
                         "identity_error": endpoint - within - boundary}

    rel_within = 0.0
    rel_boundary = 0.0
    for frame in frames:
        before = frame["head"]["before"][0] - frame["subject"]["before"][0]
        after = frame["head"]["after"][0] - frame["subject"]["after"][0]
        rel_within += after - before
    for index in range(len(frames) - 1):
        current = frames[index]["head"]["after"][0] - frames[index]["subject"]["after"][0]
        following = frames[index + 1]["head"]["before"][0] - frames[index + 1]["subject"]["before"][0]
        rel_boundary += following - current
    rel_endpoint = ((frames[-1]["head"]["after"][0] - frames[-1]["subject"]["after"][0])
                    - (frames[0]["head"]["before"][0] - frames[0]["subject"]["before"][0]))

    rig_vectors = [frame["subject_to_head"] for frame in frames]
    rig_net_vector = sub(rig_vectors[-1], rig_vectors[0])
    rig_path = sum(norm(sub(rig_vectors[index + 1], rig_vectors[index])) for index in range(len(rig_vectors) - 1))
    depth_start = frames[0]["head"]["before"][2]
    depth_end = frames[-1]["head"]["after"][2]
    camera_yaw_boundary_gaps = [
        abs(wrap_degrees(math.degrees(frames[index + 1]["camera_yaw_before"] - frames[index]["camera_yaw_after"])))
        for index in range(len(frames) - 1)
    ]
    camera_pitch_boundary_gaps = [
        abs(math.degrees(frames[index + 1]["camera_pitch_before"] - frames[index]["camera_pitch_after"]))
        for index in range(len(frames) - 1)
    ]
    within = rel_within / segment["abs_yaw"]
    boundary = rel_boundary / segment["abs_yaw"]
    endpoint = rel_endpoint / segment["abs_yaw"]
    opposed = rel_within * rel_boundary < 0
    # The overlap removed by opposite-signed terms.  Divide by two because
    # |a|+|b|-|a+b| counts the canceled magnitude once from each term.
    cancellation = (abs(rel_within) + abs(rel_boundary) - abs(rel_endpoint)) / (2.0 * segment["abs_yaw"])
    return {
        "frames_found": len(frames),
        "head": result["head"], "primary": result["primary"], "subject": result["subject"],
        "relative_within_x_per_yaw": within,
        "relative_boundary_x_per_yaw": boundary,
        "relative_endpoint_x_per_yaw": endpoint,
        "opposed": opposed,
        "cancellation_per_yaw": cancellation,
        "rig_net_vector": rig_net_vector,
        "rig_net": norm(rig_net_vector),
        "rig_horizontal_net": math.hypot(rig_net_vector[0], rig_net_vector[2]),
        "rig_vertical_net": abs(rig_net_vector[1]),
        "rig_path": rig_path,
        "depth_delta": depth_end - depth_start,
        "depth_abs_delta": abs(depth_end - depth_start),
        "depth_start": depth_start,
        "depth_end": depth_end,
        "camera_yaw_boundary_gap_max_deg": max(camera_yaw_boundary_gaps, default=0.0),
        "camera_pitch_boundary_gap_max_deg": max(camera_pitch_boundary_gaps, default=0.0),
        "start_head_relative": rig_vectors[0],
        "end_head_relative": rig_vectors[-1],
        "start_head_screen_offset": frames[0]["head"]["before"][0] - frames[0]["subject"]["before"][0],
        "duration": segment["duration"],
        "frame_count": segment["frames"],
        "yaw_rate": segment["abs_yaw"] / segment["duration"],
    }


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: V614_CAUSAL_GEOMETRY_AUDIT.py REPORT.md")
    path = Path(sys.argv[1])
    text, lines, samples, segments, pairs = parse_report(path)
    for segment in segments.values():
        segment["decomposition"] = decompose(segment, samples)

    rows = []
    for pair in pairs:
        touch = segments[pair["touch"]]
        relay = segments[pair["relay"]]
        td, rd = touch["decomposition"], relay["decomposition"]
        row = {
            "pair": pair["pair"], "touch": touch["id"], "relay": relay["id"],
            "head_h_touch": abs(touch["head"]["dx"]) / touch["abs_yaw"],
            "head_h_relay": abs(relay["head"]["dx"]) / relay["abs_yaw"],
            "head_h_difference": abs(relay["head"]["dx"]) / relay["abs_yaw"] - abs(touch["head"]["dx"]) / touch["abs_yaw"],
            "duration_touch": touch["duration"], "duration_relay": relay["duration"],
            "frames_touch": touch["frames"], "frames_relay": relay["frames"],
            "rig_net_touch": td["rig_net"], "rig_net_relay": rd["rig_net"],
            "rig_path_touch": td["rig_path"], "rig_path_relay": rd["rig_path"],
            "depth_abs_touch": td["depth_abs_delta"], "depth_abs_relay": rd["depth_abs_delta"],
            "within_touch": td["relative_within_x_per_yaw"], "within_relay": rd["relative_within_x_per_yaw"],
            "boundary_touch": td["relative_boundary_x_per_yaw"], "boundary_relay": rd["relative_boundary_x_per_yaw"],
            "endpoint_touch": td["relative_endpoint_x_per_yaw"], "endpoint_relay": rd["relative_endpoint_x_per_yaw"],
            "cancel_touch": td["cancellation_per_yaw"], "cancel_relay": rd["cancellation_per_yaw"],
            "opposed_touch": td["opposed"], "opposed_relay": rd["opposed"],
            "start_yaw_gap_deg": abs(wrap_degrees(math.degrees(relay["camera_yaw"][0] - touch["camera_yaw"][0]))),
            "start_pose_gap": norm(sub(rd["start_head_relative"], td["start_head_relative"])),
            "start_screen_offset_gap": abs(rd["start_head_screen_offset"] - td["start_head_screen_offset"]),
        }
        rows.append(row)

    routes = {}
    for route in ("touch", "relay"):
        chosen = [segments[pair[route]]["decomposition"] for pair in pairs]
        routes[route] = {
            "duration_mean": mean([entry["duration"] for entry in chosen]),
            "frames_mean": mean([entry["frame_count"] for entry in chosen]),
            "yaw_rate_mean": mean([entry["yaw_rate"] for entry in chosen]),
            "rig_net_mean": mean([entry["rig_net"] for entry in chosen]),
            "rig_path_mean": mean([entry["rig_path"] for entry in chosen]),
            "depth_abs_mean": mean([entry["depth_abs_delta"] for entry in chosen]),
            "depth_start_mean": mean([entry["depth_start"] for entry in chosen]),
            "depth_end_mean": mean([entry["depth_end"] for entry in chosen]),
            "within_abs_mean": mean([abs(entry["relative_within_x_per_yaw"]) for entry in chosen]),
            "boundary_abs_mean": mean([abs(entry["relative_boundary_x_per_yaw"]) for entry in chosen]),
            "endpoint_abs_mean": mean([abs(entry["relative_endpoint_x_per_yaw"]) for entry in chosen]),
            "cancellation_mean": mean([entry["cancellation_per_yaw"] for entry in chosen]),
            "opposed_count": sum(entry["opposed"] for entry in chosen),
            "primary_boundary_abs_mean": mean([
                abs(segments[pair[route]]["decomposition"]["primary"]["boundary_x"])
                / segments[pair[route]]["abs_yaw"] for pair in pairs
            ]),
            "subject_boundary_abs_mean": mean([
                abs(segments[pair[route]]["decomposition"]["subject"]["boundary_x"])
                / segments[pair[route]]["abs_yaw"] for pair in pairs
            ]),
        }

    summary = {
        "report": str(path), "report_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "line_count": len(lines), "frame_samples": len(samples), "eligible_segments": len(segments),
        "matched_pairs": len(pairs), "routes": routes,
        "pair_counts": {
            "relay_head_lower": sum(row["head_h_relay"] < row["head_h_touch"] for row in rows),
            "relay_rig_net_higher": sum(row["rig_net_relay"] > row["rig_net_touch"] for row in rows),
            "relay_duration_longer": sum(row["duration_relay"] > row["duration_touch"] for row in rows),
            "relay_cancellation_higher": sum(row["cancel_relay"] > row["cancel_touch"] for row in rows),
            "relay_depth_change_higher": sum(row["depth_abs_relay"] > row["depth_abs_touch"] for row in rows),
        },
        "identity_error_max": max(abs(segments[pair[route]]["decomposition"][point]["identity_error"])
                                  for pair in pairs for route in ("touch", "relay")
                                  for point in ("head", "primary", "subject")),
        "camera_boundary_continuity": {
            "yaw_gap_max_deg": max(segments[pair[route]]["decomposition"]["camera_yaw_boundary_gap_max_deg"]
                                   for pair in pairs for route in ("touch", "relay")),
            "pitch_gap_max_deg": max(segments[pair[route]]["decomposition"]["camera_pitch_boundary_gap_max_deg"]
                                     for pair in pairs for route in ("touch", "relay")),
        },
        "unmatched_start_state": {
            "camera_yaw_gap_mean_deg": mean([row["start_yaw_gap_deg"] for row in rows]),
            "camera_yaw_gap_median_deg": median([row["start_yaw_gap_deg"] for row in rows]),
            "head_pose_gap_mean_studs": mean([row["start_pose_gap"] for row in rows]),
            "head_pose_gap_median_studs": median([row["start_pose_gap"] for row in rows]),
            "head_screen_offset_gap_mean_px": mean([row["start_screen_offset_gap"] for row in rows]),
            "head_screen_offset_gap_median_px": median([row["start_screen_offset_gap"] for row in rows]),
        },
        "associations_across_28_segments": {},
        "pairs": rows,
    }

    all_segments = [segments[pair[route]] for pair in pairs for route in ("touch", "relay")]
    head_h = [abs(segment["head"]["dx"]) / segment["abs_yaw"] for segment in all_segments]
    summary["associations_across_28_segments"] = {
        "headH_vs_duration": pearson(head_h, [segment["duration"] for segment in all_segments]),
        "headH_vs_rigNet": pearson(head_h, [segment["decomposition"]["rig_net"] for segment in all_segments]),
        "headH_vs_depthAbs": pearson(head_h, [segment["decomposition"]["depth_abs_delta"] for segment in all_segments]),
        "headH_vs_cancellation": pearson(head_h, [segment["decomposition"]["cancellation_per_yaw"] for segment in all_segments]),
        "headH_vs_boundaryAbs": pearson(head_h, [abs(segment["decomposition"]["relative_boundary_x_per_yaw"]) for segment in all_segments]),
    }

    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
