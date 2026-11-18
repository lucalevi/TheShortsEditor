# 9. Colour is decided in one place

- Status: accepted
- Date: 2026-11-14

## Context

PQ frames were shown unconverted in the viewer but converted on export, and picked text colours were drawn lighter (Generic RGB).

## Decision

`RenderEngine/ColorPipeline.swift` decides colour: Rec. 709 for preview, thumbnails and the usual export, HLG for an HDR export; Core Image works in extended sRGB, non-linear, 16-bit float; HDR frames are tone-mapped with VideoToolbox; the compositor receives sources untouched. Model colours (`RGBA`) are sRGB; frame-drawing contexts come from `ColorPipeline.makeContext()`; files the app writes are tagged.

## Consequences

Viewer, thumbnails and export agree for every kind of footage in the media matrix tests. Ordinary clips in an HDR export look darker on SDR screens (the export option says so).
