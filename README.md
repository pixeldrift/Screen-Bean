# Screen Bean

### ***Your display settings, caffeinated.***

Screen Bean is a macOS tool for planning, visualizing, calibrating, and eventually controlling complex multi-display environments.

When multiple monitors have different sizes, resolutions, pixel densities, orientations, and physical positions, arranging them correctly can be difficult. MacOS provides a useful abstract representation of displays, but it doesn’t provide much help when the goal is to understand the physical relationship between the screens.

Screen Bean aims to bridge that gap.

Instead of treating displays as arbitrary pixel rectangles, Screen Bean creates a virtual physical workspace where displays can be represented according to their real-world dimensions and relationships.

---

## Current Status

Screen Bean is an early-stage prototype.

The current application can:

* Automatically detect connected displays
* Identify displays using Apple’s display APIs
* Retrieve display names
* Retrieve display resolutions
* Retrieve physical display dimensions reported by macOS
* Calculate approximate pixel density / PPI
* Track the Mac’s current display arrangement
* Represent displays in a physical coordinate system
* Preserve manually calibrated physical dimensions
* Assign persistent display identities
* Save display configurations between launches
* Display physical dimensions in the workspace
* Automatically scale the physical layout to fit the available workspace

The underlying architecture is built around a physical coordinate system so that more advanced calibration and mapping tools can be added without having to redesign the core geometry system.

---

## The Problem

A typical multi-monitor setup might contain:

* A 27” 4K monitor
* A 24” 1080p monitor
* A laptop or iMac display
* A vertically rotated display
* Displays positioned at different heights
* Displays with different pixel densities
* Displays separated by physical gaps

MacOS can represent these screens in its own coordinate system, but that representation doesn’t necessarily correspond to the physical arrangement of the monitors.

The physical relationship between displays can be more important than their raw pixel coordinates, especially for situations involving:

* Large continuous wallpapers
* Digital signage
* Multi-monitor installations
* Physical display calibration
* Accurate mouse transitions
* Visual alignment
* Photography and video production
* Exhibition or installation planning


Screen Bean is intended to make that physical relationship visible and editable.

---

## Core Concept

Screen Bean uses a physical coordinate system as its canonical representation of the display environment.

The primary workspace uses physical units rather than screen pixels.

For example:

                  Physical Workspace
        0"                           60"
        │                             │
        ▼                             ▼
        ┌───────────────────┐
        │                   │
        │     Display A     │
        │     23.6 × 13.4"  │
        │                   │
        └───────────────────┘
                  ┌─────────────────────────┐
                  │                         │
                  │       Display B         │
                  │                         │
                  └─────────────────────────┘

The physical model is independent of:

* MacOS display coordinates
* Pixel resolution
* Window size
* Screen Bean’s zoom level

Those systems become projections of the physical model.

---

## Display Detection

Screen Bean automatically detects displays connected to the Mac.

For each display, it collects information including:

* Persistent display identity
* macOS display ID
* Display name
* Pixel width
* Pixel height
* Physical width
* Physical height
* Primary-display status
* macOS screen position
* Approximate pixel density

Where MacOS provides physical dimensions, those values are retained as the detected dimensions while users can then calibrate the dimensions manually. The original detected dimensions remain available so Screen Bean can distinguish between detected and calibrated measurements.

---

## Persistent Display Identity

Display identity is separated from the runtime Core Graphics display ID.

Screen Bean uses Apple’s display UUID to identify the physical display across application launches. This can accommodate display-specific information such as:

* Nickname
* Physical dimensions
* Calibration state
* Physical position
* Rotation
* Future mapping information

Those details can then remain associated with the correct physical display.

---

## Physical Display Model

Each display is represented using physical geometry. A display has:

* X position
* Y position
* Width
* Height
* Rotation
* Persistent identity
* Nickname
* Calibration state

Based on those factors, the physical workspace can then represent displays independently of how macOS currently arranges them.

---

## Workspace

The primary workspace is intended to become an interactive physical layout editor.

Planned workspace features include:

* Pan
* Zoom
* Trackpad/mouse navigation
* Scale to Fit
* Center View
* Physical measurement grid
* Rulers
* Measurement indicators
* Display selection
* Display dragging
* Display rotation

The grid background provides physical context while remaining visually subtle. A default grid spacing of approximately 6 inches is provided, with finer subdivisions available at higher zoom levels.

---

## Display Visualization

Displays should be visually distinguishable while retaining accurate physical proportions.

Planned visualization options include:

* Display colors
* Transparency
* Bezel visibility
* Center marks
* Edge markers
* Display labels
* Resolution information
* Physical dimensions
* Calibration status

This will make it possible to work with many displays without losing track of which physical monitor corresponds to which virtual display.

---

## Layout Reference Images

Screen Bean will support importing photographs or other images as physical layout references. Reference image will appear behind the virtual displays.

Users will be able to:

* Position the image
* Scale it
* Rotate it
* Adjust transparency
* Lock it
* Toggle visibility

This will allow a user to photograph an existing display installation and align Screen Bean’s virtual displays with the actual monitors in the photograph.

### Perspective Correction

Future versions may support four-point perspective correction and image warping.

The goal is to compensate for photographs taken off access, wide angle lens distortion, etc.

Eventually, users may be able to identify the four corners of a photographed display and have Screen Bean rectify the image into the physical workspace.

---

## Unified Wallpaper Canvas

Screen Bean will eventually support importing a single image intended to span multiple displays. The display arrangement becomes a unified canvas.

For example:

    ┌──────────────────┬──────────────────────────┐
    │                  │                          │
    │    Display A     │        Display B         │
    │                  │                          │
    ├──────────────────┼──────────────────────────┤
    │                  │                          │
    │    Display C     │        Display D         │
    │                  │                          │
    └──────────────────┴──────────────────────────┘
              One unified image

Users will be able to:

* Import an image
* Position it
* Scale it
* Crop it
* Preview it across the complete display arrangement
* Toggle clipping to hide or dim areas of the image outside the displays
* Generate individual images for each display

The slicing process should account for each display's properties.

* Resolution
* Pixel density
* Physical size
* Position
* Rotation
* Orientation
* Relative location within the unified physical canvas

The goal is to produce output appropriate for displays with different physical sizes and resolutions while maintaining the intended physical composition.

---

## Layout Export

Screen Bean will eventually export layouts as PNG, SVG, or PDF

Exports may include:

* Display outlines
* Display names
* Physical dimensions
* Grid
* Measurement annotations
* Guides
* Reference images
* Bezel outlines
* Calibration markers

This will make Screen Bean useful not only as a configuration tool but also as a documentation and installation-planning tool.

---

## Mouse Calibration

One of the more advanced goals for Screen Bean is a Mouse Calibration/Alignment Mode.

The physical arrangement of displays doesn’t always correspond cleanly to their rectangular MacOS coordinate boundaries.

Screen Bean would allow users to visually define how the mouse transitions between displays.

### Transport Zones

A user could select an edge or section of an edge on one display and connect it to another display.

For example:

    ┌──────────────┐ ─────▶┌──────────────┐
    │              │       │              │
    │   Display A  │       │   Display B  │
    │              │       │              │
    └──────────────┘ ─────▶└──────────────┘

The connected region becomes a mouse transport zone.

When the mouse exits Display A through that region, Screen Bean can map the mouse position to the corresponding region of Display B.

### Point-Based Mapping

Transport zones should not be limited to complete edges. Users should eventually be able to establish relationships between arbitrary points. Screen Bean can use these correspondence points to calculate an interpolated mapping. This could allow unusual display arrangements and transitions that aren’t possible with simple rectangular edge matching.

### Corner Mapping

Corners should be usable as calibration points. This could eventually support mouse transitions that follow the physical topology of unusual multi-display installations.

----

## Alignment Guides

Screen Bean will support guides generated from selected displays.

Default guides may include:

* Left edge
* Right edge
* Top edge
* Bottom edge
* Horizontal center
* Vertical center

Users should also be able to create custom guides. Guides can be projected into the virtual physical workspace and used to compare alignment between displays.

For example:

    Display A                         Display B
    │                                 │
    │──────────── Guide ──────────────│
    │                                 │
    │                                 │

Dragging or adjusting a guide should provide visual feedback on the corresponding location of other displays.

---

## Snapping

Alignment tools will support snapping.

* Option - Temporarily disable snapping
* Shift - Constrain movement

Snapping targets could include:

* Display edges
* Display corners
* Display centers
* Grid intersections
* Guide lines

---

## Calibration Patterns

Screen Bean will be able to display calibration patterns on the physical displays.

* Grids
* Crosshairs
* Center marks
* Edge markers
* Numbered points
* Measurement references
* Alignment targets
* Continuous guides spanning multiple displays

These patterns should make it possible to compare the virtual model against the physical installation.

---

## Consistent Physical Scale

Different displays can have dramatically different pixel densities.

Screen Bean should therefore distinguish between pixel dimensions and physical dimensions.

A calibration mode could allow reference elements such as icons, system menus, cursors, etc to be displayed at the same physical size across displays.

For example, a 1-inch reference marker should represent approximately one physical inch regardless of whether it is displayed on a 1080p monitor or a high-density Retina display.

Initially this will focus on Screen Bean’s own calibration and visualization tools. Global control over how third-party MacOS applications render their UI may not be possible without deeper system integration.

---

## Architecture

Screen Bean is being designed around a canonical physical coordinate system. The physical workspace is the source of truth. This separation is intentional.

It allows the application to evolve from a simple visualization tool into a more sophisticated calibration and mapping system without making the UI coordinate system the foundation of the application.

---

## Current Architecture

The project currently includes several foundational components.

#### DisplayInfo

Represents information detected from macOS about a physical display.

It contains:

* Runtime display ID
* Persistent display ID
* Display name
* Pixel dimensions
* Detected physical dimensions
* Current calibrated physical dimensions
* Display position
* Primary-display state
* PPI calculation

#### PhysicalLayout

Provides the physical coordinate system used by Screen Bean. The current model uses 1 unit as 1 physical inch, though this might be adjustable in settings to CM for international users. Other measurements are then derived from this base unit.

* Layout bounds
* Width
* Height
* Display rectangles
* Physical points
* Display gaps

#### DisplayConfiguration

Represents Screen Bean’s persistent configuration for a display.

It stores:

* Persistent display ID
* Nickname
* Physical dimensions
* Physical X/Y position
* Rotation
* Calibration state

#### DisplayConfigurationStore

Provides persistent storage for display configurations using UserDefaults and Codable.

This allows Screen Bean to restore display-specific configuration between launches.

#### DisplayArrangementView

The interactive workspace. Draws the grid and displays from the `PhysicalLayout`, and handles pan, zoom, selection and dragging.

#### DisplayInspectorView

The sidebar for editing the selected display: nickname, physical size, position, color and bezels.

---

## Development Roadmap

Organized by topic. Checked items are built.

### Foundation

* [x]	Detect displays automatically
* [x]	Read display names
* [x]	Read pixel dimensions
* [x]	Read physical dimensions
* [x]	Calculate PPI
* [x]	Establish persistent display identity
* [x]	Establish physical coordinate system
* [x]	Create persistent display configuration model
* [x]	Save and restore display configuration
* [x]	Display physical dimensions
* [x]	Automatically scale the layout to the available workspace

### Workspace

* [x]	Pan, zoom, scale to fit, center view and a physical measurement grid
* [x]	Select, multi-select, drag, resize from grab handles, and lock displays
* [x]	Display color coding and bezel visibility
* [x]	Detect each display's rotation and mirroring from macOS
* [x]	Refresh displays and open System Settings
* [x]	Undo and redo for layout edits (Edit menu, Command-Z and Shift-Command-Z)
* [x]	Add Virtual Display: create displays that aren't connected, from a known size and place, so layouts can be planned before hardware is set up (projectors, for example)
* [x]	Virtual displays stay in the layout while disconnected, with a corner icon showing whether each is connected or virtual
* [x]	Assign a virtual display to a physical display later
* [x]	Keep when disconnected: a connected display can leave a stand-in in the layout while unplugged, which hands back to the real display when it returns
* [x]	New connected displays are offered a link to a virtual display, so the plan and the real screen never both show
* [x]	Layout presets: save the whole setup (display positions, sizes, bezels, colors, locks, guides, images) under a name, such as Work or Home, and switch between them
* [x]	Presets remember which displays were connected and suggest the matching preset when the connected displays change
* [x]	Colored border on the real display when its virtual display is selected
* [x]	Identify displays on the real screens (stays on; optionally excluding the primary)
* [x]	Overlay windows on every display, so tools can draw outside the app window
* [x]	Rulers (can be hidden) and alignment guides, one tool drawn across all displays
* [x]	Measurement guides: distance across the gaps between displays, draggable
* [x]	Custom guides dragged from the rulers
* [x]	Snap to guides and to bezels while dragging (Control flips snapping)
* [x]	Modifier keys: Shift constrains or unlinks, Option transforms from the opposite side or zooms from view center, Control flips snapping, Z (held) turns a drag into a zoom, Option-scroll pans up and down and Shift-Option-scroll pans sideways
* [x]	Shift snaps rotation to 15 degree steps (images; displays follow if arbitrary display rotation is added)
* [x]	Displays sidebar on the left, collapsible, with List and Thumbnail views and the Refresh Displays and Add Virtual Display buttons

### Display Settings

* [x]	Edit physical dimensions, position, name, color and bezels
* [x]	Show detected vs. calibrated size, with a Reset to detected button
* [x]	Allow entering the diagonal measurement
* [x]	Add Aspect Ratio, with a lock; recalculate the other sizes when one measurement is edited

### Wallpaper

* [x]	Import wallpaper; create a unified physical canvas
* [x]	Position, scale, rotate, flip and stretch wallpaper
* [x]	Fit an image to the selected displays, or to all displays
* [x]	Preview wallpaper across displays, optionally clipped to the displays (bezels stay on top)
* [x]	Preview the wallpaper full screen across all real displays
* [x]	Live preview: wallpaper across the real screens that updates as you edit, with this window on top
* [x]	Lock wallpaper
* [x]	Account for display rotation
* [x]	Calculate output resolution
* [x]	Slice the unified image into per-display images
* [x]	Export display-specific wallpaper files
* [x]	Apply wallpaper to each display

### Reference Image

* [x]	Import, position, scale, rotate, flip and stretch a reference image
* [x]	Adjust opacity and whether it draws above or below the displays
* [x]	Lock reference image
* [x]	Align to Display: click a display's four corners in the photo (any order) to scale, turn and place the reference image on it (best fit; photos are never perfect), or mark a line of known length to set only the scale

### Global Options

* [x]	Type fractional measurements (for example "23 1/8") in number inputs
* [x]	Toggle number inputs between decimal and fractions (nearest 16th)
* [x]	Measurement units: centimeters vs. inches (stored in inches; a unit typed after a number, like "60 cm", is always understood)

### Mouse Mapping

* [x]	Show Mouse Transit: zones found automatically between facing displays (the whole of the two edges linked, corner to corner), drawn as translucent shapes with each edge colored for the display it connects to. Select a zone to move its end dots along a display's outline (they snap to corners and can go around a corner) or slide a whole side with its middle dot. Edits are remembered; Delete removes a zone
* [x]	Mouse mapping engine (first version): an event tap makes the pointer cross by the transit zones, matching the crossing point proportionally along the other edge; outside any zone macOS's own behavior applies. Runs inside the app, which keeps going from a menu bar icon when the window is closed (with Launch at Login). Needs Accessibility permission and no app sandbox
* [ ]	Test and tune mouse mapping on real hardware (hot corners, fast flicks, drags, corners)
* [ ]	Move the engine into a separate login-item helper so it runs without the app
* [ ]	Edge-segment mapping
* [ ]	Corner mapping
* [ ]	Point correspondence and interpolation

### Advanced Calibration

* [x]	Guide projection and cross-display alignment

### Export & Documentation

* [x]	Export PNG/SVG template

### Backlog

Rarely needed, so these wait until the main topics are working.

* [ ]	Rotate displays to arbitrary angles (angled installations)
* [ ]	Corner Pin Alignment mode (warped/un-warped view), a four-corner perspective correction for the reference image
* [ ]	Rotate (90° steps) and flip displays in Screen Bean's layout. Rotation is already detected from System Settings, so this is only for planning; it needs saved turns applied after detection, and flips honored when slicing the wallpaper
* [ ]	Media Composer: more than a single reference image or wallpaper, with several items arranged together (photo collages, for example) and other media types, such as video spanned across all screens
* [ ]	Export installation diagrams, measurement annotations and calibration specs
* [ ]	Use the GPU for the live preview (including video) so it doesn't lag

---

## Design Principles

Screen Bean should follow a few core principles as development continues.

***Physical reality first.*** The physical arrangement of the displays should be the canonical model. Don’t confuse pixels with inches. Resolution describes pixels. Physical dimensions describe the real-world display. Both are important, but they describe different things.

***Visualization before automation.*** The user should be able to see and understand a proposed configuration before Screen Bean attempts to modify system behavior.

***Calibration should be measurable.*** Whenever possible, Screen Bean should provide visual references, measurements, and explicit correspondence points rather than relying on guesswork.

***Progressive complexity.*** Basic display arrangement should remain simple. Advanced tools such as image warping and mouse mapping should become available when needed without overwhelming the basic workflow.

***Preserve detected information.*** When the user calibrates a display, Screen Bean should preserve the original information reported by macOS rather than destroying it. This allows users to understand what was detected and what they changed.

---

## Long-Term Vision

The long-term goal is for Screen Bean to become a visual calibration and spatial mapping environment for multi-display systems.

A user should be able to:

1. Connect several displays
2. Have Screen Bean automatically identify them
3. Measure or calibrate their physical dimensions
4. Arrange them in a virtual physical workspace
5. Photograph the real installation
6. Align the virtual displays with the photograph
7. Correct perspective or lens distortion
8. Import a unified image and preview it across the entire installation
9. Export per-display wallpaper
10. Visually calibrate mouse transitions between displays
11. Create guides and alignment references
12. Export the complete installation as a documented layout

The ultimate goal is not simply to provide another display-arrangement utility. It is to create a tool that understands where displays physically exist in space and how their pixels, geometry, and interactions relate to one another.

These display configuration tools can also be used with projectors. The same 4k resolution that is measured in pixels per inch for monitor is often measured in pixels per foot on a large projection. This could be used for a "foveated" display, where a lower density projected image is paired as a contextual extension of the main monitor, like peripheral vision. This setup is called a "focus-plus" display.

https://www.patrickbaudisch.com/projects/focuspluscontextscreens/applications/index.html

Similar approaches are used in video playback and routing systems for live events where multiple projectors and LED walls are combined with arbitrary positions, shape, and sizes.

