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

The goal is to compensate for photographs taken off access, wide angle lense distortion, etc.

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

---

## Development Roadmap

### Phase 1 — Foundation

* [x]	Detect displays automatically
* [x]	Read display names
* [x]	Read pixel dimensions
* [x]	Read physical dimension's
* [x]	Calculate PPI
* [x]	Establish persistent display identity
* [x]	Establish physical coordinate system
* [x]	Create persistent display configuration model
* [x]	Save display configuration
* [x]	Restore display configuration
* [x]	Display physical dimensions.
* [x]	Automatically scale the layout to the available workspace

### Phase 2 — Interactive Physical Workspace

* [ ]	Pan workspace
* [ ]	Zoom workspace
* [ ]	Scale to Fit
* [ ]	Center View
* [ ]	Physical measurement grid
* [ ]	Rulers
* [ ]	Select displays
* [ ]	Drag displays
* [ ]	Rotate displays
* [ ]	Edit physical dimensions
* [ ]	Display calibration UI
* [ ]	Display color coding
* [ ]	Bezel visibility
* [ ]	Display transparency

### Phase 3 — Visual Calibration

* [ ]	Import reference image
* [ ]	Position reference image
* [ ]	Scale reference image
* [ ]	Rotate reference image
* [ ]	Adjust reference transparency
* [ ]	Lock reference image
* [ ]	Four-corner perspective correction
* [ ]	Image warping
* [ ]	Lens/perspective compensation
* [ ]	Calibration patterns
* [ ]	Measurement guides
* [ ]	Alignment guides
* [ ]	Custom guides

### Phase 4 — Unified Wallpaper

* [ ]	Import wallpaper
* [ ]	Create unified physical canvas
* [ ]	Position and scale wallpaper
* [ ]	Preview wallpaper across displays
* [ ]	Account for display gaps
* [ ]	Account for display rotation
* [ ]	Calculate output resolution
* [ ]	Slice unified image into per-display images
* [ ]	Export display-specific wallpaper files

### Phase 5 — Mouse Mapping

* [ ]	Mouse calibration mode
* [ ]	Edge transport zones
* [ ]	Edge-segment mapping
* [ ]	Corner mapping
* [ ]	Arbitrary point correspondence
* [ ]	Coordinate interpolation
* [ ]	Custom mouse transition paths
* [ ]	Physical-topology-based transitions
* [ ]	Snapping and modifier-key controls

### Phase 6 — Advanced Calibration

* [ ]	Display-generated guide projection
* [ ]	Cross-display guide alignment
* [ ]	Multi-point calibration
* [ ]	Automated geometric transformations
* [ ]	Physical-scale calibration
* [ ]	Consistent reference-element sizing
* [ ]	Advanced perspective correction
* [ ]	Automated display-corner detection

### Phase 7 — Export & Documentation

* [ ]	PNG layout export
* [ ]	SVG layout export
* [ ]	PDF layout export
* [ ]	Installation diagrams
* [ ]	Measurement annotations
* [ ]	Calibration reports
* [ ]	Reusable layout templates

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

These display configuration tools can also be used with projectors. The same 4k resolution that is measured in pixels per inch for monitor is often messured in picels per foot on a large projection. This could be used for a "foveated" display, where a lower density projected image is paired as a contextual extension of the main monitor, like peripheral vision. This setup is called a "focus-plus" display.

https://www.patrickbaudisch.com/projects/focuspluscontextscreens/applications/index.html

Similar approaches are used in video playback snd routing ststems for live events where multiple projectors and LED walls are combined with arbitary positions, shape, and sizes.

