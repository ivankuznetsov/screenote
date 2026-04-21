---
title: AnnotationCropService
type: service
source: app/services/annotation_crop_service.rb
created: 2026-04-10
updated: 2026-04-10
tags: [service, image-processing, annotation, crop]
---

# AnnotationCropService

TLDR: Crops a region around an annotation from a screenshot image. Returns a Base64-encoded image. Handles both point annotations (fixed 200x200 crop) and region annotations (crop with 50px padding). Results are cached for 1 hour.

Source: `app/services/annotation_crop_service.rb`

## Purpose

When MCP tools return annotations to AI agents, they include a cropped image of the annotated region so the agent can see exactly what the human is commenting on. This service produces those crops.

## Interface

```ruby
# Class method (convenience)
AnnotationCropService.crop(screenshot, annotation)
# => Base64-encoded PNG/JPEG string

# Instance method
service = AnnotationCropService.new(screenshot, annotation)
service.crop
```

## Inputs

- `screenshot` -- A [[screenshot]] record with `image` attached, `width` and `height` set
- `annotation` -- An [[annotation]] record with percentage-based coordinates

## Output

- Base64-encoded binary string of the cropped image (PNG or JPEG, matching source format)

## Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `POINT_CROP_SIZE` | 200 | Pixels: width/height of crop for point annotations |
| `REGION_PADDING` | 50 | Pixels: padding around region annotations |
| `MAX_DIMENSION` | 1072 | Max width/height of output (resized if larger) |

## Logic

### Point annotations (`annotation.point?`)
1. Convert percentage coordinates to pixel coordinates using screenshot dimensions
2. Crop a 200x200 area centered on the annotation point
3. Clamp to image bounds
4. Resize to fit within 1072x1072

### Region annotations
1. Convert percentage coordinates to pixel coordinates
2. Crop the region with 50px padding on each side
3. Clamp to image bounds
4. Resize to fit within 1072x1072

## Caching

Results are cached in Rails.cache (Solid Cache) with key: `annotation_crop/{annotation.id}/{annotation.updated_at}/{blob.checksum}`. Expires in 1 hour. The cache key includes the blob checksum so re-uploads invalidate the cache.

## Dependencies

- `image_processing` gem (with libvips backend)
- Active Storage (to open blob files)
- Rails.cache (Solid Cache)

See also: [[models/annotation]], [[models/screenshot]], [[architecture]]
