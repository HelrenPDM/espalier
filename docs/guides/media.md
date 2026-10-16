# Media

Lessons show images, vector graphics and videos through two block kinds:
`figure` shows an image or an SVG file with its text alternative and a
caption, and `video` plays a video with its captions and a transcript. Each
installation keeps one media library. Authors upload files there, and the
import of a content pack moves the files of its folder `media/` there. A
background job converts every raster image to WebP and every video to WebM
with VP9 and Opus, rebuilds every SVG file from an allowlist and checks every
WebVTT file. The library keeps only these delivery files, and the pack export
and the SCORM export write them, so a content pack stays the only import and
export format (README section 15, decisions D18 and D19).

This guide describes the accepted files, the conversion, the settings and
limits, the library, the media of a content pack, captions and transcripts,
external files and embeds with the CSP they produce, the malware scan, the
browser support, and the backup of the media store.
[`content-packs.md`](content-packs.md), section "Media", gives every rule of
the folder `media/` and of both block kinds,
[`pack-workbench.md`](pack-workbench.md) the media entries of a draft, and
[`scorm-export.md`](scorm-export.md) the media of a SCORM package.

## Accepted files

The platform detects the kind of a file from its leading bytes
(`Espalier.Media.Sniff`) and then compares the extension of its file name, in
lower case, with the extensions of that kind. It reads at most the first
1 MiB of the file for this, in the BEAM, before any other program opens it.

| Kind | Extensions | Signature at the start of the file | Largest file | Delivery format |
|---|---|---|---|---|
| Image | `.png` | `89 50 4E 47 0D 0A 1A 0A` | `MEDIA_IMAGE_MAX_MB`, default 20 (20,971,520 bytes) | WebP (`.webp`) |
| Image | `.jpg`, `.jpeg` | `FF D8 FF` | as above | WebP |
| Image | `.gif` | `GIF87a` or `GIF89a` | as above | WebP |
| Image | `.webp` | `RIFF`, four bytes, `WEBP` | as above | WebP |
| SVG | `.svg` | after an optional UTF-8 byte order mark and white space: `<?xml`, `<svg` or `<!--` | 1,048,576 bytes (`svg_max_bytes`) | SVG (`.svg`), rebuilt |
| Video | `.mp4`, `.m4v`, `.mov` | `ftyp` at offset 4, with no HEIF or AVIF brand (below) | `MEDIA_VIDEO_MAX_MB`, default 1024 (1,073,741,824 bytes) | WebM (`.webm`) with VP9 and Opus |
| Video | `.webm`, `.mkv` | `1A 45 DF A3` | as above | WebM with VP9 and Opus |
| Captions | `.vtt` | after an optional UTF-8 byte order mark: `WEBVTT`, followed by a space, a tab, a line break or the end of the file | 524,288 bytes (`captions_max_bytes`) | WebVTT (`.vtt`), stored as written |

A file whose leading bytes match no signature of the table answers
`unsupported_type`, and a file whose extension belongs to another kind than
its signature answers `extension_mismatch`, for example a PNG file named
`clip.mp4`. An `ftyp` box whose major brand or one of whose compatible
brands within the first 64 bytes is `mif1`, `mif2`, `msf1`, `heic`, `heix`,
`heim`, `heis`, `hevc`, `hevx`, `hevm`, `hevs`, `avif`, `avis` or `avio`
answers `unsupported_type`, so HEIC photos and AVIF images are refused also
under the extension `.mp4`. AVIF, HEIC, TIFF, BMP and RAW images, audio
files, HLS and DASH playlists and text files other than SVG and WebVTT are no
media files of the platform.

For an image, the detection also reads the width and the height from the
header: the `IHDR` chunk of a PNG file, the logical screen of a GIF file, the
`VP8 `, `VP8L` or `VP8X` chunk of a WebP file, and the first `SOFn` segment of
a JPEG file within the first 1 MiB. Width times height above 40,000,000
(`max_input_pixels`) answers `too_many_pixels`, so a small file that declares
a huge picture never reaches a decoder. A PNG file whose `acTL` chunk comes
before its first `IDAT` chunk is an APNG, and a WebP file with the animation
flag in its `VP8X` chunk is an animated WebP.

These checks run when the upload or the import receives the file. A file
that fails them is refused at once, and no ffmpeg or ffprobe process starts
for it.

## Settings

`Espalier.RuntimeConfig` reads these variables at boot. An invalid value stops
the boot with a message that names the variable
([`self-hosting.md`](self-hosting.md), section "How the settings are read").
An empty value counts as unset.

| Variable | Default | Values | Effect |
|---|---|---|---|
| `MEDIA_DIR` | required in production; `tmp/media` in development, `tmp/test-media` in tests | a directory | The root of the media store. `compose.yaml` sets `/data/media` in the volume `media`. |
| `MEDIA_IMAGE_MAX_MB` | `20` | a positive integer | The largest raster image in MB of 1,048,576 bytes. SVG and WebVTT files have the fixed limits of the table above. |
| `MEDIA_VIDEO_MAX_MB` | `1024` | a positive integer, at most 2047 while `MEDIA_CLAMAV_SOCKET` is set | The largest video in MB. clamd scans at most 2 GiB per file, so a larger value with a scanner stops the boot with `MEDIA_VIDEO_MAX_MB must be at most 2047 while MEDIA_CLAMAV_SOCKET is set`. |
| `MEDIA_VIDEO_MAX_MINUTES` | `60` | a positive integer | The longest video. |
| `MEDIA_VIDEO_MAX_HEIGHT` | `1080` | an integer from 240 to 2160 | The height of a converted video. |
| `MEDIA_IMAGE_MAX_EDGE` | `2560` | an integer from 320 to 8192 | The longest edge of a converted image. |
| `MEDIA_STORAGE_MAX_GB` | `50` | a positive integer | The storage quota of the delivery files, posters and incoming files, in GB of 1,073,741,824 bytes (section "Limits and quota"). |
| `MEDIA_EXTERNAL_HOSTS` | empty | comma-separated entries `host` or `host:port` | The hosts that may serve external video files (section "External files and embeds"). |
| `MEDIA_EMBED_HOSTS` | empty in production and tests; `embed.espalier.test` in development | the same | The hosts whose players may run in an iframe. |
| `MEDIA_EMBED_CONSENT` | `click` | `click` or `auto` | `click` loads an embedded player after the learner agrees; `auto` loads it with the page. |
| `MEDIA_CLAMAV_SOCKET` | unset | an absolute path of at most 107 bytes | The Unix socket of clamd; set, it switches the malware scan on (section "Malware scan"). |
| `MEDIA_FFMPEG_THREADS` | `2` | an integer from 1 to 16 | The threads of each ffmpeg and ffprobe process. |

An entry of `MEDIA_EXTERNAL_HOSTS` or `MEDIA_EMBED_HOSTS` takes no scheme, no
path and no IPv6 address, because a CSP source cannot name an IPv6 address
(`<NAME> holds an IPv6 address, which a CSP source cannot name`). An entry
of `MEDIA_EMBED_HOSTS` must not name the host of `PUBLIC_URL`, with or
without a port (`MEDIA_EMBED_HOSTS must not name the host of PUBLIC_URL`),
because a same-origin iframe with `allow-scripts` and `allow-same-origin`
could leave its sandbox. Whoever changes a variable restarts `app`, because
the boot reads the values and builds the CSP from them.

In production, the boot also checks the tools of the media processing
(`Espalier.Media.Ffmpeg.check/0`): `ffmpeg`, `ffprobe` and `timeout` must be
on the path, ffmpeg must be release 7.1 or later, and it must list the
encoders `libvpx-vp9`, `libopus`, `libwebp` and `libwebp_anim` and the
demuxers `mov`, `matroska`, `png_pipe`, `jpeg_pipe`, `webp_pipe`, `gif` and
`apng`. Each missing piece stops the boot with its own line, such as
`ffmpeg lacks the encoder libvpx-vp9`. The image installs the `ffmpeg`
package of Debian trixie, release 7.1.5, and the development shell
`ffmpeg-headless` 8.1.2 of the pinned nixpkgs.

## Limits and quota

`config :espalier, :media` in `config/config.exs` holds the fixed limits.
`Espalier.Media` reads them, and a value that is no positive integer raises
`ArgumentError` at the first read.

| Limit | Value | Applies to |
|---|---|---|
| `svg_max_bytes` | 1,048,576 | an SVG file |
| `captions_max_bytes` | 524,288 | a WebVTT file |
| `max_input_pixels` | 40,000,000 | width times height of an input image, checked in the header and passed to ffmpeg and ffprobe as `-max_pixels` |
| `max_video_pixels` | 8,294,400 (3840 by 2160) | width times height of a video frame, passed as `-max_pixels` and checked in the probe |
| `max_frames` | 1,000 | the frames of an animated image |
| `image_timeout_seconds` | 120 | all commands of an image, SVG or captions job together |
| `video_timeout_factor` | 25 | the deadline of a video conversion: `max(video_timeout_floor_seconds, video_timeout_factor * duration)` |
| `video_timeout_floor_seconds` | 600 | the shortest deadline of a video conversion |
| `heartbeat_seconds` | 60 | the interval at which a running job sets the time of the last change of its asset |
| `stale_processing_seconds` | 600 | the age of the last change after which the sweep fails an asset in `processing` with `interrupted` |
| `max_pack_media` | 500 | the media files of one content pack |
| `max_draft_media` | 500 | the media entries of one workbench draft |
| `export_max_mb` | 1,024 | the media of one SCORM package and of one draft download, in MB |

`config :espalier, :media_retention, unused_days: 30` sets the retention of
unused imported files (section "Deletion and retention").

### The storage quota

The used bytes are the sum of the delivery file, the poster and the incoming
file of every asset. Two assets that share a delivery file or a poster, such
as two JPEG files that differ only in their EXIF data, each count it, so the
sum can overstate the disk use. An upload or an import that would take the
sum above `MEDIA_STORAGE_MAX_GB` answers `storage_full`: 409 on the upload, an
error entry at the path of the file in the report of a pack import. The check
runs in the transaction of the ingest under the advisory lock
`espalier.media`, so two concurrent uploads count one after the other. A
conversion and its poster can be larger than the upload, so the job checks
the quota again before the asset becomes `ready`, and a conversion beyond it
fails with `storage_full` and leaves no file in the store.

### Space beyond the quota

The quota counts the stored and the incoming files. The volume of
`MEDIA_DIR` needs space beyond it for three kinds of temporary files:

| Directory | Content | Largest size |
|---|---|---|
| `uploads/` | The body of every upload while it arrives (`PLUG_TMPDIR`, section "The media store") | the larger of `MEDIA_IMAGE_MAX_MB` and `MEDIA_VIDEO_MAX_MB` per upload in progress |
| `work/<asset id>-<run id>/` | The delivery file and the poster of a running job until it moves them into the store; each run of a job has a directory of its own | one converted file and one poster per job: two image jobs and one video job of the server, and one more for an import that `mix espalier.import` or `Espalier.Release.import_pack/2` runs next to it |
| `work/<uuid>/` | The staging directory of a draft download with its zip | the zip of the draft, with up to `export_max_mb` of media, per download; at most two downloads of drafts run at once per node (`max_parallel_downloads` of `config :espalier, :pack_drafts`), and a download keeps its slot from the zip build until its zip is sent and removed |

The staging directory holds the media files of a draft as hard links to the
store, so they take no further space; the zip does. The SCORM export copies
the media of a module into `EXPORT_DIR` when that directory lies on another
file system, as in `compose.yaml`, so the volume `exports` needs up to twice
`export_max_mb` for a build next to the packages that it keeps
([`scorm-export.md`](scorm-export.md)).

## The media store

`Espalier.Media.Store` owns every path below `MEDIA_DIR`:

| Path | Content |
|---|---|
| `files/<aa>/<bb>/<sha256>.<ext>` | the delivery files and posters, named by the SHA-256 hex digest of their bytes; `<aa>` and `<bb>` are its first four hex digits, and `<ext>` is `webp`, `svg`, `webm` or `vtt` |
| `incoming/<asset id>` | an uploaded or imported file that waits for its job |
| `work/<asset id>-<run id>/` | the outputs of one run of a job, with a new run id for each run |
| `work/<uuid>/` | the staging directory of a draft download |
| `uploads/` | the temporary files of `Plug.Upload`, with `PLUG_TMPDIR=/data/media/uploads` in `compose.yaml` |

Every path is built from `MEDIA_DIR` and a digest, an extension of that list
or a UUID; no title and no file name of an upload becomes part of a path. A
file that several assets share is stored once and removed only when no asset
names it any longer. `compose.yaml` places the uploads on the volume of the
store, so an upload moves into `incoming/` by a rename without a copy. The
directory lies outside `priv/static`, and only the media route serves its
files (section "The media route").

## Conversion

A background job converts each new asset. The asset is `queued` until a job
takes it, `processing` while the job runs, and `ready` or `failed` at the end.
The jobs run in the Oban queues `media` (images, SVG files and captions, two
jobs at a time) and `media_video` (videos, one job at a time), each with one
attempt ([`operations.md`](operations.md), section "Background jobs").

| Input | Delivery file | Settings |
|---|---|---|
| A still image: PNG, JPEG, a GIF or APNG with one frame, a WebP without animation | WebP | at most `MEDIA_IMAGE_MAX_EDGE` pixels on the longer edge, scaled down with the aspect ratio kept and never scaled up; lossless (`-lossless 1 -compression_level 6`) for PNG, GIF and lossless WebP inputs, quality 82 for JPEG and lossy WebP inputs; no metadata (`-map_metadata -1`) |
| An animated GIF or APNG with at most 1,000 frames | animated WebP | the same scale, `libwebp_anim` at quality 80, endless loop, no metadata; the poster is the first frame as a still WebP at quality 80 |
| An animated WebP | animated WebP | the structural path below; the poster is the first frame |
| SVG | SVG | rebuilt from an allowlist (section "SVG files") |
| WebVTT | WebVTT | checked and stored as written (section "Captions files") |
| A Matroska or WebM file with VP9 in `yuv420p` without alpha, no audio or Opus audio, and at most `MEDIA_VIDEO_MAX_HEIGHT` pixels high | WebM | remuxed without a new encoding: the first video stream and the first audio stream are copied, metadata and chapters dropped |
| Every other video: MP4 and MOV files, VP8, AV1, H.264, Vorbis, other pixel formats and VP9 with alpha | WebM | the first video stream with `libvpx-vp9` (`-crf 32 -b:v 0 -deadline good -cpu-used 4 -row-mt 1 -g 240 -pix_fmt yuv420p`), scaled down to at most `MEDIA_VIDEO_MAX_HEIGHT` pixels in height, and the first audio stream with `libopus` at 96 kbit/s in two channels; subtitle and data streams, metadata and chapters dropped |

A video without a video stream fails with `no_video_stream`, a video longer
than `MEDIA_VIDEO_MAX_MINUTES` with `too_long`, and a frame above 3840 by 2160
pixels with `too_many_pixels`. ffmpeg applies the rotation of a video while
it converts it. The poster of a video is the frame at one second, or at a
tenth of the duration for a video shorter than ten seconds, as a WebP at
quality 80 with the size of the video. A remuxed video passes the VP9 and Opus
streams of the upload unchanged to the browsers.

The facts of an asset come from its delivery file: width and height, and for
an image whether it holds transparent pixels (`has_alpha`) and whether it
moves (`animated`); for a video the duration and whether it has sound
(`has_audio`); for captions the end of the last cue as duration.

### Orientation and colour

Both supported ffmpeg builds (8.1.2 of the development shell and 7.1.5 of
Debian trixie) read the EXIF orientation of a JPEG and apply it while they
convert: a photo with orientation 6 (rotated by 90 degrees) becomes an
upright WebP, and the stored width and height are those of the upright
picture. The WebP holds no EXIF data afterwards, so no viewer turns it a
second time.

The conversion converts no colour space, and neither build writes the ICC
profile of the input into the WebP: a JPEG or PNG with a Display P3 profile
becomes a WebP without an `ICCP` chunk. Browsers show such a WebP as sRGB,
so a photo with wide-gamut colours loses saturation. An author who needs
those colours exports the photo in sRGB before the upload.

### HDR and alpha in videos

The conversion applies no tone mapping. An HDR video (PQ or HLG) becomes
8-bit `yuv420p` without a mapping of its brightness range to SDR, so its
picture can differ from the original in brightness and colour. An author who
needs control over the result converts an HDR video to SDR before the
upload.

`-pix_fmt yuv420p` holds no alpha channel. A video with transparency, such as
VP9 with alpha, loses it in the conversion, and its transparent areas become
opaque. An image keeps its alpha channel in WebP.

### Animated WebP inputs

Neither ffmpeg build decodes an animated WebP, and the animated WebP is the
delivery format of every animation, so a pack that this platform exports
holds such files. `Espalier.Media.WebpAnim` therefore checks an animated WebP
in the BEAM and decodes no frame: the RIFF size equals the file size, every
chunk fits the file, the chunks follow the order `VP8X`, an optional `ICCP`,
`ANIM`, one or more `ANMF`, then optional `EXIF` and `XMP `, the canvas stays
within 40,000,000 pixels and the frames within 1,000, every frame rectangle
lies within the canvas, and every frame holds an optional `ALPH` chunk and one
`VP8 ` or `VP8L` chunk of the size of the frame. It then writes the file anew
without `ICCP`, `EXIF` and `XMP `, and the frame data pass unchanged.

The poster is built from the chunks of the first frame. When the first frame
covers the whole canvas, the poster is a still WebP of that frame. The
animation encoder of libwebp crops even the first frame against a
transparent canvas, so an animation whose first picture has a transparent
margin starts with a smaller frame; its poster is then an animated WebP with
that single frame on the canvas, which browsers show as a still picture. No
decoder takes part in either case. A file that breaks the structure fails
with `unsupported_animation` and the reason `structure`, and a file with more
than 1,000 frames fails with `unsupported_animation` and the reason
`too_many_frames`. A file with a structural fault converts when it is saved
as an animated GIF and uploaded again, because a GIF takes the ffmpeg path.

### SVG files

`Espalier.Media.Svg` writes every SVG file anew from an allowlist. The element
allowlist is `tags.svg` and `tags.svgFilters` of DOMPurify 3.4.17 plus `use`,
and the attribute allowlist is `attrs.svg` and `attrs.xml` of the same
release, each name in its SVG 1.1 spelling such as `viewBox`, `clipPath` and
`linearGradient`. The rebuild drops:

- `script`, `foreignObject`, `iframe`, `metadata`, the animation elements
  `animate`, `animateColor`, `animateMotion`, `animateTransform` and `set`,
  and `mpath`, each with its content;
- every element outside the SVG namespace, and every attribute with a prefix
  other than `xlink:href`, `xlink:title`, `xml:id` and `xml:space`, such as
  the `sodipodi:*` and `inkscape:*` attributes of Inkscape;
- every attribute whose name starts with `on`;
- every `href` and `xlink:href` whose value is no reference `#<id>` into the
  same file;
- the element `a`, whose children stay in its place;
- comments.

These files fail with `invalid_svg` and a reason:

| Reason | Cause |
|---|---|
| `too_large` | more than 1,048,576 bytes, in the upload or in the rebuilt file |
| `encoding` | no UTF-8, or an XML declaration that names another encoding |
| `doctype` | a `DOCTYPE` declaration |
| `entity` | an entity declaration |
| `processing_instruction` | a processing instruction other than the XML declaration |
| `parse_error` | XML that is not well-formed, a start tag with more than 1,000 attributes, an element nested deeper than 256 levels, or more than 64 namespace declarations in scope of one element |
| `root` | a root element other than `svg` in the SVG namespace |
| `embedded_image` | an `image` element anywhere in the file |
| `css` | in a kept attribute value, a `style` attribute or a `style` element: a `url(` other than `url(#<id>)`, `@import`, `expression(`, `image-set(`, `-webkit-image-set(`, `image(`, `cross-fade(`, `element(`, `src(`, a backslash, a quoted string that reaches a line break or the end of the text, or a comment or an unquoted `url(` without its end |
| `animation` | an `@keyframes` rule or one of the properties `animation`, `animation-*`, `transition` and `transition-*`, also after the `}` of a nested rule and in a selector such as `.transition:hover` |

The rebuild writes some characters as entity references, so its file can
be larger than the upload. A rebuilt file above 1,048,576 bytes fails with
`too_large` as well, because a pack that carries it, from
`mix espalier.export` or a draft download, would fail the size check of
its import.

The CSS checks read every attribute that the rebuild keeps, so a single
apostrophe in a kept attribute, such as `xlink:title="Don't"`, rejects the
file with `css`. Write the apostrophe as `’` (U+2019) there, or remove the
attribute. The text of `title` and `desc` elements is no CSS and may hold
any apostrophe. Words inside quoted CSS strings count as no property, so
`content: "transition"` passes.

An SVG file with an embedded raster image is refused, because the raster
would keep its metadata and pass an unconverted image to the browsers.
Upload such a raster as an image of its own and place it with a second
`figure`, or remove it from the drawing. A clone or symbol that Inkscape
links to another file is a `use` element with a reference outside the file;
the rebuild drops that reference, and the element then shows nothing. Unlink
such clones in Inkscape (Edit, Clone, Unlink Clone) before the export of the
drawing. Clones within the file, clip paths and gradients with
`xlink:href="#<id>"` stay. The width and the height of an SVG file come from
the `width` and `height` of its root, or from its `viewBox`.

The player shows an SVG file only through `<img>`, in which no script of the
file runs, and the media route serves it with a `sandbox` CSP.

### Captions files

`Espalier.Media.WebVtt` checks a WebVTT file and stores it unchanged. These
files fail with `invalid_captions` and a reason:

| Reason | Cause |
|---|---|
| `too_large` | more than 524,288 bytes |
| `encoding` | no UTF-8 |
| `nul` | the character U+0000 |
| `header` | no `WEBVTT` header |
| `too_many_cues` | more than 10,000 cues |
| `timing` | a cue timing line that does not read `hh:mm:ss.ttt --> hh:mm:ss.ttt` or `mm:ss.ttt --> mm:ss.ttt` with optional cue settings, a cue that ends before it starts, or a block that is no cue, no `NOTE` and no `REGION` |
| `style` | a `STYLE` block |

A `STYLE` block is refused, so no captions file brings CSS into the player.

### Failures and timeouts

A failed asset shows its failure code, and for some codes a reason, in the
library. The job logs every failure that it records as `media asset <id>
failed: <code>`, with the reason in parentheses where there is one, except a
finding of the malware scan, which the security event `upload_validation`
records ([`../security/logging.md`](../security/logging.md)). A job whose
asset was deleted, or failed by the sweep, meanwhile records no failure and
logs its stop instead (below).

| Code | Cause |
|---|---|
| `too_many_pixels` | an image above 40,000,000 pixels or a video frame above 3840 by 2160, found by ffmpeg or ffprobe |
| `too_many_frames` | an animated GIF or APNG with more than 1,000 frames |
| `too_long` | a video longer than `MEDIA_VIDEO_MAX_MINUTES` |
| `no_video_stream` | a video file without a video stream |
| `unsupported_animation` | an animated WebP that fails the structural check, with the reason `too_many_frames` for more than 1,000 frames and `structure` for every other fault |
| `invalid_svg` | an SVG file that the rebuild refuses |
| `invalid_captions` | a WebVTT file that the check refuses |
| `malware_found` | a finding of the malware scan |
| `scan_failed` | a failed scan: an exceeded limit of clamd, no connection, no answer in time or an answer that the platform does not read |
| `storage_full` | the quota, checked again before the asset becomes `ready` |
| `conversion_failed` | ffmpeg or ffprobe ended with an error, the delivery file could not be read, or the job ended with an exception |
| `timeout` | the deadline of the job passed |
| `interrupted` | the job stopped, for example at a restart of the server, and the sweep ended it |

Each job has one deadline for all its commands after the scan: 120 seconds
for an image, an SVG file or captions, and `max(600, video_timeout_factor *
duration) + 120` seconds for a video, with the duration of its probe. Every
ffmpeg and ffprobe process runs under `timeout --kill-after=10`, which ends
it at the deadline and kills it ten seconds later, so a process ends also
when the node that started it stops. The jobs of `media` and `media_video`
run once. While a job runs, it sets the time of the last change of its asset
every `heartbeat_seconds` (60), also during the scan, the probes and a
remux, which report no progress. A heartbeat or a progress update that
fails, for example while the database is away, is skipped, and the job goes
on. An exception in the job ends its running ffmpeg or ffprobe as a stop
does (see below) and then fails the asset with `conversion_failed` at once.
A job that ends without a status, at a stop or restart of the server, at a
Ctrl-C of `mix espalier.import` or when Oban kills it at its job timeout,
leaves its asset in `processing`, and its heartbeat ends with it.
`Espalier.Media.StaleWorker` runs every 15 minutes and fails with
`interrupted` every asset in `processing` whose last change lies more than
`stale_processing_seconds` (600) back. While a server runs, such an asset
therefore fails within about 25 minutes of the end of its job, for a video
as for an image. Until then, an upload or an import of the same file returns
the asset in `processing`; a failed asset converts again when the same file
is uploaded or imported again.

A job also stops when its asset is deleted, or failed by the sweep, while it
runs. A running ffmpeg or ffprobe stops at the next progress update of a
video conversion, about every two seconds, or at the next heartbeat: the job
sends `TERM` to it through `timeout`, which kills a process that has not
ended ten seconds later. Between two steps the job reads the status of its
asset: after the scan, before each ffmpeg or ffprobe, and before it writes
the output of the SVG rebuild, the captions check or the check of an
animated WebP. The scan, the SVG rebuild, the captions check and the check
of an animated WebP run to their end once they have started, the scan at
most until the timeout of clamd and the SVG rebuild at most until the
deadline of the job, so a job of every kind stops at the latest when its
current step ends. The job then starts no further command, stores no file,
changes no status and logs `media asset <id> stopped, because it is no
longer processing` at `info`, and its queue slot is free again. A result or
a failure that a job reaches after the deletion or the sweep changes no row
and logs the same line in place of a failure line. `kill` from the Debian
package `procps`, which the image installs, sends the signal; without `kill`
on the `PATH`, a stopped command runs until it ends or reaches its deadline,
and the log shows a warning.

Every ffmpeg and ffprobe process starts as a program of its own with an
argument list and without a shell, reads its input with a forced format and
`-protocol_whitelist file`, so no playlist, data reference or concat list
opens a network connection or another file, and runs with
`-max_alloc 536870912` (512 MiB per allocation), the pixel limit of its kind
as `-max_pixels` and `MEDIA_FFMPEG_THREADS` threads.

## The library

A person with the role `author` reaches the library at `/admin/media` through
the entry "Media" in the author section of the admin navigation. The page has
an upload zone for several files with a progress bar per file, filters for
the kind, the status and unused files, a search by title, and a grid of
cards. Each card shows a preview (the image, the SVG file, the poster of a
video, or an icon for captions), the title, the kind, the size and the
status, while a job runs with its progress, and for a failed asset the text
of its code and reason. The page asks for the status every two seconds while
an asset is `queued` or `processing`.

A card opens the detail dialog: the preview, the facts, the title with an
edit field, the uses with links, "Copy directive", "Add to draft" and
"Delete". "Copy directive" copies a directive for a lesson, such as
`:::figure{src=media/team-chart.webp alt="" provenance=invented}`, whose empty
`alt` or `title` the validator refuses until the author fills it in. "Add to
draft" adds the asset to a draft of the pack workbench at a path that the
author chooses ([`pack-workbench.md`](pack-workbench.md), section "Media").

Every change needs a second factor from the last 10 minutes (README section
6.4): the upload, the title change and the deletion. Without one, the server
answers 403 `reauth_required`, and the page opens the step-up dialog before
it sends the file. The title of a new asset is the file name without its
extension. A title and a file name hold at most 255 characters, counted
as code points as PostgreSQL counts them, so a letter with a combining
accent (as macOS writes file names) counts twice and an emoji sequence
counts each of its code points; the upload cuts a longer name after a
whole character and keeps the extension of the file name. The library
keeps no original: a converted file replaces the upload, so an author who
needs the original keeps it in the repository of the organization.

An upload of a file whose bytes equal the source of an existing asset, or the
delivery file of an existing `ready` asset, answers 200 with that asset in
place of a new one. A pack that `mix espalier.export` wrote on this
installation therefore imports into the assets it came from. An asset that
`failed` before starts again with the new copy of the same file.

### Routes

The routes belong to the rows "Media library" and "Media files" of README
section 8. Every answer under `/api/admin` carries `cache-control: no-store`.
A request without a session answers 401 `unauthenticated`, and a person
without the role `author` gets 403 `forbidden`.

| Route | Pipelines | Answers |
|---|---|---|
| `GET /api/admin/media` with `kind`, `status`, `unused`, `q`, `limit` (1 to 100, default 50) and `after` | `[:api, :author]` | 200 `items` and `next`, a cursor for the next page or `null`; newest first |
| `GET /api/admin/media/:id` | `[:api, :author]` | 200 the asset with `uses`: the published programs, the drafts with their paths, and the validated imports |
| `POST /api/admin/media` with exactly one `multipart/form-data` part `file` with a file name, streamed to disk; every other part stays unread | `[:api, :author_write, :media_upload]` | 201 a new asset, 200 an existing asset of the same file; 400 `bad_request` for a body that is no valid multipart, such as an empty body or one without its closing boundary; 409 `storage_full`, also when the media volume is full or the disk quota of the user that runs the server is exhausted, while the body arrives or while the file moves into the store; 413 `request_too_large` above the larger of `MEDIA_IMAGE_MAX_MB` and `MEDIA_VIDEO_MAX_MB`, and for the headers of a part above 16 KiB; 415 `unsupported_media_type` for a body that is no `multipart/form-data`; 422 `validation_failed` with `fields.file` `["unsupported_type"]`, `["extension_mismatch"]`, `["too_large"]` (the limit of the detected kind) or `["too_many_pixels"]`, `fields.file` `["invalid_type"]` for a part `file` without a file name or with an empty one, and `unexpected_field` for every other part |
| `PATCH /api/admin/media/:id` with `{title}` (1 to 255 characters) | `[:api, :author_write]` | 200 the asset |
| `DELETE /api/admin/media/:id` | `[:api, :author_write]` | 204; 409 `asset_in_use` with `uses` while a program or a draft uses the asset |

The asset holds `id`, `kind`, `status`, `failure`, `failure_detail`,
`progress`, `title`, `source_name`, `origin` (`upload` or `pack`), `ext`,
`bytes`, `width`, `height`, `duration_ms`, `has_audio`, `animated`,
`has_alpha`, `url` and `poster_url` (set while it is `ready`), `inserted_at`
and `updated_at`. The OpenAPI document at `GET /api/openapi` names the
accepted types, their signatures and the limits in the operation of the
upload.

### Deletion and retention

A deletion locks the asset, refuses it with 409 `asset_in_use` while a
program or a draft uses it, and otherwise deletes the row and writes the
audit event `media.deleted` in one transaction. The files go after the
commit, each only when no other asset names it. A validated import that
names a deleted asset can no longer be published (section "Media in content
packs"). A deletion while the asset is `processing` stops its job: a running
ffmpeg or ffprobe at the next progress update of a video conversion, about
every two seconds, or at the next heartbeat, at most `heartbeat_seconds`
(60) later, and the scan, the SVG rebuild, the captions check or the check
of an animated WebP when that step ends. The job then starts no further
command, stores no file, logs its stop at `info` and frees its queue slot
(section "Failures and timeouts").

`Espalier.Media.RetentionWorker` runs every day at 03:45 UTC and deletes every
asset of origin `pack` whose last change lies more than 30 days back
(`unused_days`) and that no program, draft or validated import uses. Every
import and every upload of the same file sets the time of the last change
again. Assets of origin `upload` stay until an author deletes them, and an
upload of a file that an import brought gives its asset the origin `upload`.

An upload of a new file and an upload that restarts a failed asset of the
same file write the audit event `media.uploaded` with the kind, and a
deletion writes `media.deleted`. An import writes no media event; its
`pack.imported` covers the files. An upload or an import by an author that
restarts a failed asset makes that author its uploader, so a scan of the
new copy names the author who brought it.

## Media in content packs

A content pack carries its media files in the folder `media/` at its root,
up to three directories deep and at most 500 files (`max_pack_media`). The
loader checks the path and the size of every file and reads none of them.
[`content-packs.md`](content-packs.md), section "Media", gives every rule.

```text
my-pack/
  pack.yaml
  media/
    release-checks.svg
    module-1/
      assistant-demo.webm
      assistant-demo-en.vtt
      assistant-start.png
  modules/
    01-basics/
      lessons/01-first-lesson.md
```

```markdown
:::figure{src=media/release-checks.svg alt="Four steps from left to right: generated draft, mark the statements, check each source, initials and release" size=medium provenance=invented}
The release checks of a generated notice.
:::

:::video{src=media/module-1/assistant-demo.webm title="A test pattern with a tone" poster=media/module-1/assistant-start.png captions="media/module-1/assistant-demo-en.vtt:en" provenance=invented}
A moving test pattern with colour bars and a counter, and a steady tone.
:::
```

| Block | Attribute | Value |
|---|---|---|
| `figure` | `src` | required; the media path of an image or an SVG file of the pack |
| `figure` | `alt` | the text alternative, 1 to 1,000 characters; required unless `decorative=true`, and not allowed with it |
| `figure` | `decorative` | `true` only; the player gives the image an empty text alternative |
| `figure` | `size` | `small`, `medium` or `full` (default) |
| `video` | `src` | the media path of a video file of the pack, or an external `https:` URL of a `.webm` or `.mp4` file; exactly one of `src` and `embed` |
| `video` | `embed` | the `https:` URL of the player of a streaming service |
| `video` | `title` | required, 1 to 255 characters |
| `video` | `poster` | the media path of an image of the pack; of an animated image the video shows the first frame; only with `src` |
| `video` | `captions` | one to eight entries `<media path>:<language>`, separated by commas, each a `.vtt` file and a BCP 47 tag, each language once (compared without regard to case, so `pt-BR` and `pt-br` are one language); only with `src` |

The body of a `figure` is its caption, and the body of a `video` its
transcript; both may be empty within the rules of the section "Captions and
transcripts". The Markdown image syntax `![alt](src)` is an error in every
block body (`use a figure block for images`), and the player renders an
image of older text as its text alternative.

### Import and publish

The import ingests every file below `media/` that a block names; files that
no block names stay out of the library. Each file takes the checks of the
section "Accepted files", and a refused file is an error at its path, which
fails the import. Two paths that would get the same delivery path are an
error as well, such as `media/photo.jpg and media/photo.png both become
media/photo.webp; rename one`. The upload of the pack page and the workbench
import queue the jobs for the running server. `mix espalier.import` and
`Espalier.Release.import_pack/2` run the jobs of their import in their own
process before the publish, because they start no Oban queue, and wait for a
server that has taken a job first; with `--draft` or `draft: true`, the jobs
stay queued for the running server.

A program is published only when every media file of its import is `ready`.
`POST /api/admin/packs/:id/publish` answers 409 `media_not_ready` with one
entry per file that is `missing`, `queued`, `processing` or `failed` with its
code, and `mix espalier.import` prints one line `<path>: <status>` per entry
and exits with status 1. The pack page lists the media of the import with
their status, asks for it every two seconds while a file is `queued` or
`processing`, and keeps "Publish" disabled until every file is `ready`. The
diff of the publish dialog lists added, changed and removed media paths.

### Export

`mix espalier.export` writes every media file in its delivery format and
names the delivery paths in the directives, so a pack whose source held
`media/photo.jpg` and `media/clip.mp4` is written with `media/photo.webp` and
`media/clip.webm`. From that first export on, the pack round-trips: its import
on the same installation finds the existing assets by the digest of their
delivery files. When two assets share one delivery file, the import takes the
asset that the program of the pack key already uses, so the publish dialog
lists no media change; a draft that the pack workbench starts from the zip
archive of the pack attaches the same assets. Another installation converts
the files again: a lossless WebP keeps its pixels, a lossy WebP is encoded
again at quality 82, SVG and WebVTT files stay byte for byte, and a WebM file
that meets the remux rule is copied without a new encoding.

## Captions and transcripts

The validator requires captions or a transcript for a video file of the pack
and for an external file, and a transcript for an embed, because it cannot
look into the player of another service. That is the minimum it can check.
WCAG 2.2 asks for more, and the rest is the task of the author:

| Success criterion | Level | What it asks | What the platform checks |
|---|---|---|---|
| 1.2.1 Audio-only and Video-only (Prerecorded) | A | a text alternative for a video without sound that presents the same information, or an audio track | a transcript or captions for every video |
| 1.2.2 Captions (Prerecorded) | A | captions for the sound of every video with sound | the pack page lists every video file with sound and without `captions` as a hint, because the validator does not know the audio track |
| 1.2.3 Audio Description or Media Alternative (Prerecorded) | A | an audio description, or a text alternative that describes the picture as well as the sound (a descriptive transcript) | nothing; the author writes the transcript accordingly |
| 1.2.5 Audio Description (Prerecorded) | AA | an audio description where the picture carries information that the sound does not | nothing; the platform has no audio description track, so the information belongs in the narration of the video or in the transcript |

The player shows the transcript under the video in a disclosure "Transcript",
closed at the start, and offers each captions file as a `<track>` of kind
`captions`, the first one as the default track. Captions are files of the
pack below `media/` and text files of a workbench draft, so authors write and
correct them in the editor of the workbench.

## Animated images

An animated image shows its first frame, the poster, with a button "Play
animation". The button swaps the poster for the animation, and "Pause
animation" swaps it back. The animation never starts by itself, also when
the browser reports no preference for reduced motion (WCAG 2.2 2.2.2). No
video plays by itself either, and an animated image that a video names as its
`poster` shows only its first frame.

## External files and embeds

A `video` block takes, in place of a file of the pack, an external video file
or the player of a streaming service. The server fetches neither of them:
the browsers of the learners load them from their hosts.

| Kind | Attribute | Allowlist | Player |
|---|---|---|---|
| External file | `src` with an `https:` URL of a `.webm` or `.mp4` file | `MEDIA_EXTERNAL_HOSTS` | a `<video>` element with `preload="none"` and the note "Plays from <host>"; nothing loads before the learner presses play |
| Embed | `embed` with an `https:` URL | `MEDIA_EMBED_HOSTS` | an `<iframe>` that loads after the learner agrees, or with the page under `MEDIA_EMBED_CONSENT=auto` |

The upload of the pack page, the check and the import of the workbench,
`mix espalier.import` and `Espalier.Release.import_pack/2` report a host
outside its list as an error at the line of the block, for example
`host cdn.example.org is not in MEDIA_EXTERNAL_HOSTS`. An entry without a
port admits port 443 only, and an entry with a port admits that port.
`mix espalier.validate` checks no host, because it runs without the settings
of an installation. A host that leaves its list after the publish makes the
player show "This video is not available on this installation." in place of
the video. HLS and DASH streams (`.m3u8`, `.mpd`) play through the player of
their service as an embed.

### The click-to-load notice

Before the learner agrees, an embed shows a notice: "This video plays in a
player of <host>. Loading it sends the address of your device and data of
your browser to <host>." with the buttons "Load video" and "Open on <host>".
"Open on <host>" opens the player in a new tab with
`rel="noopener noreferrer"`. "Load video" loads the iframe and every other
embed of the same host on the page. The page keeps the agreement in memory
and stores nothing. The agreement holds for the life of the page, also when
the learner moves on to another lesson or module. It ends with a reload and
with every sign-out and sign-in, also one in another tab of the browser, so
the next person in the tab is asked again. The SCORM package has no
setting, so an embed in a package always shows the notice.

The iframe carries `sandbox="allow-scripts allow-same-origin
allow-presentation allow-popups allow-popups-to-escape-sandbox"`,
`allow="fullscreen; picture-in-picture; encrypted-media"`,
`referrerpolicy="strict-origin-when-cross-origin"` and `loading="lazy"`. The
player of the other service runs with its own origin and reads nothing of the
page.

`MEDIA_EMBED_CONSENT=auto` loads every embed with the page, so the player
reaches its host as soon as a learner opens the lesson. README section 10
lists the players of external streaming services among the topics of the
GDPR workstream.

### The CSP of the allowlists

While both lists are empty, every page carries the CSP of README section 6.5:

```text
default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'
```

A host in `MEDIA_EXTERNAL_HOSTS` appends `media-src 'self'` with the host,
and a host in `MEDIA_EMBED_HOSTS` appends `frame-src` with the host, each in
the order of the variable and with `https://` in front. With

```sh
MEDIA_EXTERNAL_HOSTS=cdn.example.org,media.example.net:8443
MEDIA_EMBED_HOSTS=player.example.org
```

the CSP reads:

```text
default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; media-src 'self' https://cdn.example.org https://media.example.net:8443; frame-src https://player.example.org
```

`object-src 'none'` and `base-uri 'none'` stay in every case. The application
builds the CSP once at start, so a change of a list takes effect with the
restart of `app`.

## The media route

`GET /media/<sha256>.<ext>` serves the delivery files and posters to
signed-in users. An author reads every `ready` file; a learner reads a file
only while a published program uses its asset. Every other request answers
404, so the route tells nobody whether a file exists. A request without a
session answers 401 `unauthenticated`, and an enrollment session 403
`enrollment_required`. The name must be 64 lower-case hex digits, a dot and
`webp`, `svg`, `webm` or `vtt`.

| Header | Value |
|---|---|
| `content-type` | `image/webp`, `image/svg+xml; charset=utf-8`, `video/webm` or `text/vtt; charset=utf-8`, fixed by the extension |
| `content-security-policy` | `default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; sandbox`, also on 304, 401 and 404 |
| `content-disposition` | `inline; filename="<sha256>.<ext>"` |
| `cache-control` | `private, max-age=31536000, immutable`, also with a `vsn=` query |
| `etag` | the quoted digest, so `If-None-Match` answers 304 |
| `accept-ranges` | `bytes`; a single range answers 206, an unsatisfiable range 416 |

The other headers of README section 6.5 stay, among them
`x-content-type-options: nosniff` and `cross-origin-resource-policy:
same-origin`, so another site cannot embed a media file. The route answers
404 for a `Sec-Fetch-Dest` that does not fit the type: `image` or `document`
for WebP and SVG, `video`, `audio` or `document` for WebM, and `track` or
`document` for WebVTT. A request without that header passes.

### Cached files and the sign-out

A media file does not change under its name, so the browser keeps it in its
private cache for up to a year. The sign-out (`DELETE /api/session`) answers
with `Clear-Site-Data: "cache"`, and the browser then drops the files that it
cached for the origin. That header arrives only with a sign-out. A session
that ends otherwise, through the inactivity limit, the absolute limit, an end
by an admin or a closed browser, leaves the cached files in the browser until
it evicts them. On a shared device, learners sign out at the end, or the
device clears its browser data.

## Malware scan

With `MEDIA_CLAMAV_SOCKET` set, every uploaded and imported file passes a
clamd scan before ffprobe, ffmpeg, the XML parser of the SVG rebuild or the
WebVTT check reads it. Only the signature and header check of the section
"Accepted files", which reads at most the first 1 MiB in the BEAM, runs
before the scan. The job sends the file over the Unix socket with the clamd
command `INSTREAM` in chunks of 1 MiB and waits 60 seconds plus one second per
4 MiB for the answer, 316 seconds for a file of 1024 MiB, so that the
`MaxScanTime` of clamd answers first.

| Answer of clamd | Result |
|---|---|
| `stream: OK` | the conversion runs |
| `stream: <signature> FOUND` | the asset fails with `malware_found`, the incoming file is deleted, and the security event `upload_validation` names the uploader and the signature; after a restart of a failed asset by an upload or an import of an author, the uploader is that author |
| `stream: Heuristics.Limits.Exceeded.<limit> FOUND`, `INSTREAM size limit exceeded`, no connection, no answer in time, a closed connection, any other answer | the asset fails with `scan_failed` and the reason `limits_exceeded`, `size_limit`, `connect`, `timeout`, `closed` or `reply`, and the log names the asset and the reason |

The scan fails closed: a file that clamd did not scan completely never
converts. The application opens no other connection for the scan and needs
no TLS for it, because the socket lies in a volume of the same host.

### The clamd example

`docs/guides/examples/compose.clamav.yaml` adds a service `clamav` with the
image `clamav/clamav:1.5.4` and the configuration
`docs/guides/examples/clamd.conf`. Both services mount the volume
`clamd-socket` at `/run/clamav`, and `app` receives
`MEDIA_CLAMAV_SOCKET=/run/clamav/clamd.sock`. `app` starts once clamd answers
its health check, which can take several minutes at the first start while
freshclam fetches the signatures.

```sh
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml up -d
```

| Setting of `clamd.conf` | Value | Purpose |
|---|---|---|
| `LocalSocket` | `/run/clamav/clamd.sock` | the only listener; there is no `TCPSocket` |
| `LocalSocketMode` | `666` | the user `nobody` of `app` connects; only containers that mount the volume reach the socket |
| `StreamMaxLength`, `MaxFileSize`, `MaxScanSize` | `1100M` | above the largest upload of the default `MEDIA_VIDEO_MAX_MB` |
| `MaxScanTime` | `220000` (milliseconds) | the longest scan: three times the longest scan of a file of 1024 MiB that was measured with the example |
| `AlertExceedsMax` | `yes` | every exceeded limit becomes a `Heuristics.Limits.Exceeded` answer, so such a file fails with `scan_failed` |

`StreamMaxLength`, `MaxFileSize` and `MaxScanSize` must cover
`MEDIA_VIDEO_MAX_MB`, and `MaxScanTime` the scan of the largest file. Whoever
raises `MEDIA_VIDEO_MAX_MB` raises these four values with it. clamd keeps its
signatures in memory: the service used 954 to 979 MiB after its start
(ClamAV 1.5.4 with the signatures of 2026-10-15), and up to 1.9 GiB while
clamd loaded new signatures next to the old ones after an update. The scan
of a video of 1024 MiB took up to 73 seconds on a development machine under
load, including the transfer over the socket. `MaxScanTime` also limits the
scan of plain data, and an exceeded limit answers
`Heuristics.Limits.Exceeded.MaxScanTime`. A stream above `StreamMaxLength`
makes clamd answer `INSTREAM size limit exceeded` and close the connection.
The job records `scan_failed` with the reason `size_limit` when it reads
that answer, and with the reason `closed` when the socket closes before the
answer is read; with `clamav/clamav:1.5.4`, the example measured `closed`.
The `/init` script of the image runs freshclam next to clamd, which fetches
new signatures from `database.clamav.net` once a day; that download is the
only network connection of the service.

### Testing the scan

`docs/guides/examples/espalier-test.ndb` holds one signature,
`Espalier.Test.Marker`, which matches the text `ESPALIER-CLAMAV-TEST-MARKER`
in any file. clamd loads every signature file of its database directory,
`/var/lib/clamav` in the image. A mount of the file there stops the service,
because the `/init` script of the image changes the owner of every file in
that directory: a read-only mount fails that step, and a writable mount
would hand the file on the host to the user of the image. The test
therefore copies the signature into the running service and has clamd load
it:

```sh
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml \
  cp docs/guides/examples/espalier-test.ndb clamav:/var/lib/clamav/espalier-test.ndb
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml \
  exec clamav clamdscan --reload
```

Then upload a WebVTT file whose `NOTE` block holds the marker:

```text
WEBVTT

NOTE ESPALIER-CLAMAV-TEST-MARKER

00:00:00.000 --> 00:00:02.000
A test cue.
```

The upload answers 201, the asset turns `failed` with `malware_found`, and the
log holds one line with `"event":"upload_validation"` and the reason
`malware_found:Espalier.Test.Marker.UNOFFICIAL`. clamd marks every signature
outside the official databases with `.UNOFFICIAL`. A stop of the service
(`docker compose stop clamav`) makes the next upload fail with `scan_failed`
and the reason `connect`. The test ends with the removal of the signature,
another reload and the deletion of the failed test asset in the library:

```sh
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml \
  start clamav
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml \
  exec clamav rm /var/lib/clamav/espalier-test.ndb
docker compose -f compose.yaml -f docs/guides/examples/compose.clamav.yaml \
  exec clamav clamdscan --reload
```

### Without a scanner

Without `MEDIA_CLAMAV_SOCKET`, no scan runs. This deviates from ASVS 5.4.3,
which the matrix records with its reason (decision D19,
[`../security/asvs-l2.md`](../security/asvs-l2.md), section "Deviations"). The
other controls stay: only authors with a second factor from the last 10
minutes upload; the signature allowlist admits PNG, JPEG, GIF, WebP, SVG, MP4,
Matroska and WebVTT files only; ffmpeg writes every still image, every GIF
and APNG and every converted video anew; an animated WebP is written anew in
the BEAM without its metadata chunks, while its frame bitstreams pass
unchanged into the delivery file and the poster (section "Animated WebP
inputs"); a remuxed video gets a new WebM container from ffmpeg, while its
VP9 and Opus streams pass unchanged (section "Conversion"); every SVG file is
rebuilt, and every WebVTT file is checked; no file is executed; and the media
route serves files only to signed-in users, with a `sandbox` CSP and
`nosniff`.

## Browser support

The player delivers videos as WebM with VP9 and Opus and images as WebP.
caniuse lists for Safari on macOS and on iOS:

| Feature (caniuse) | Safari on macOS | Safari on iOS |
|---|---|---|
| `webm` (WebM video format) | full from 16.0; 14.1 to 15.6 on macOS 11.3 or later | full from 17.4 |
| `opus` (Opus audio format) | in WebM from 17.4 (17.4 with a known regression); from 18.4 on macOS 15.4 or later | in WebM from 17.4 (17.4 with a known regression), full from 18.4 |
| `webp` (WebP image format) | full from 16.0; 14 to 15.6 on macOS 11 or later | full from 14.0 |

The table follows caniuse as of 2026-10-13. A video of the platform, WebM
with VP9 and Opus, therefore plays in Safari from 17.5 (18.4 and later on
macOS 15.4 or later) and in iOS Safari from 17.5, fully from 18.4. In the
browsers of the development shell, Chromium 147 and Firefox 148 played a
converted video with its captions and answered a seek with byte ranges. The
WebKit build of Playwright plays media only with the GStreamer plugins of the
shell on its plugin path (`GST_PLUGIN_SYSTEM_PATH_1_0`), and then played the
video as well; WebKit on Linux decodes through GStreamer and says nothing
about Safari.

A browser that plays no WebM shows the text "Your browser cannot play this
video." inside the video element. For learners on such a browser, an
external MP4 file on a host of `MEDIA_EXTERNAL_HOSTS` remains possible, and
the transcript carries the content of every video.

## People in images and videos

A photo or a recording can show an identifiable person, whose image is
personal data. The organization obtains the consent of every person shown
before it publishes such a file, and it records that consent outside the
platform. The library keeps no consent record and no link from a file to a
person. README section 10 lists media that show identifiable persons among
the topics of the GDPR workstream. The conversion removes EXIF data, among
them the location and the serial number of a camera, from every image, and
the metadata of every video.

## Backup

`MEDIA_DIR/files/` and `MEDIA_DIR/incoming/` belong to the backup of an
instance, taken at the same moment as the database dump. The database names
every delivery file by its digest, so a restored database without `files/`
shows assets whose files are missing, and a publish or an export with them
fails. The job of a queued asset reads its file only from `incoming/<asset
id>`, so a restored database without `incoming/` holds queued assets whose
jobs find no file and fail. `work/` and `uploads/` hold temporary files
only. [`operations.md`](operations.md), section "Backup and restore of the
media store", gives the commands that save and restore the files together
with the database.

## Packages and downloads

The media of one module in a SCORM package, delivery files and posters
together, stay within `export_max_mb`, 1,024 MB. Above it, the export fails
with "The media of this module exceed 1024 MB; link large videos with an
external URL." A draft download of the pack workbench has the same limit and
answers 409 `download_too_large` above it. Both write `.webp` and `.webm`
entries without compression, because these formats are compressed already.
[`scorm-export.md`](scorm-export.md) describes the media of a package.

## The demo media

The demo pack carries `content/demo/media/release-checks.svg`, a diagram of
the release checks in module 2, `assistant-demo.webm`, a video of eight
seconds at 640 by 360 pixels with a test pattern and a tone in module 1, and
its captions `assistant-demo-en.vtt`. `scripts/demo-media.sh` writes the video
again with the VP9 and Opus settings of the converter:

```sh
nix-shell --run scripts/demo-media.sh
```
