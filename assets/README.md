# Assets Directory

This directory contains branding assets for the `try` project, including logos, icons, and design concepts.

## Directory Structure

```
assets/
├── README.md           # This file - usage guidelines
├── logos/              # Final, approved logo files
│   ├── svg/           # Vector formats (primary)
│   ├── png/           # Raster formats (various sizes)
│   └── ico/           # Icon formats
└── concepts/          # Design concepts and mockups
    └── proposals/     # Community-submitted proposals
```

## Logo Usage Guidelines

### When to Use the Logo

The `try` logo should be used in:
- **README.md** header or hero section
- **Documentation** sites and guides
- **Package manager** listings (Homebrew, Nix)
- **Social media** profiles and posts
- **Presentations** about the project
- **Stickers/swag** for community events

### File Format Guidelines

#### SVG (Preferred)
- **Use for:** Web, documentation, scalable contexts
- **Benefits:** Infinite scaling, small file size, editable
- **Location:** `assets/logos/svg/`

#### PNG
- **Use for:** Social media, package managers, fixed-size contexts
- **Sizes needed:**
  - `16x16` - Favicon, small icons
  - `32x32` - Standard icons
  - `64x64` - Medium icons
  - `128x128` - Large icons
  - `256x256` - High-res displays
  - `512x512` - Social media, marketing
- **Location:** `assets/logos/png/`

#### ICO
- **Use for:** Windows icons, favicons
- **Location:** `assets/logos/ico/`

### Color Modes

All logo files should support:
- **Dark mode:** Optimized for dark backgrounds (terminal default)
- **Light mode:** Optimized for light backgrounds (documentation)
- **Monochrome:** Single-color version for special contexts

### Naming Convention

```
try-logo-[variant]-[mode]-[size].[ext]

Examples:
- try-logo-primary-dark.svg
- try-logo-primary-light.svg
- try-logo-icon-dark-256x256.png
- try-logo-wordmark-mono.svg
```

### Clear Space

Maintain clear space around the logo equal to the height of the logo itself to ensure visibility and impact.

### Minimum Size

- **Digital:** 32x32 pixels minimum
- **Print:** 0.5 inches minimum

### Don'ts

❌ Don't stretch or distort the logo  
❌ Don't change the logo colors arbitrarily  
❌ Don't add effects (shadows, glows, etc.)  
❌ Don't place on busy backgrounds without sufficient contrast  
❌ Don't rotate the logo  

## Contributing Design Assets

### Submitting New Concepts

1. **Create your design** following the philosophy in [LOGO_CONCEPTS.md](../LOGO_CONCEPTS.md)
2. **Export in multiple formats:**
   - SVG (primary)
   - PNG (at least 512x512)
   - Include both dark and light mode versions
3. **Place in** `assets/concepts/proposals/[your-name]/`
4. **Submit a PR** with:
   - Design files
   - Brief description of concept
   - Rationale for design choices
   - Reference to any related issues

### Design Requirements

All logo submissions should:
- ✅ Work in both dark and light modes
- ✅ Be legible at small sizes (32x32px minimum)
- ✅ Reflect the developer-centric, minimal aesthetic
- ✅ Be provided in vector format (SVG)
- ✅ Include a monochrome version
- ✅ Be original work or properly licensed

## Integration Points

### README.md
```markdown
<p align="center">
  <img src="assets/logos/svg/try-logo-primary-dark.svg" alt="try logo" width="200">
</p>
```

### Documentation Sites
```html
<img src="/assets/logos/svg/try-logo-primary-light.svg" 
     alt="try" 
     class="logo">
```

### Homebrew Formula
```ruby
# In Formula/try.rb
desc "Fresh directories for every vibe"
homepage "https://github.com/tobi/try"
# Logo can be referenced in tap metadata
```

### Nix Package
```nix
# In flake.nix meta
meta = {
  description = "Fresh directories for every vibe";
  homepage = "https://github.com/tobi/try";
  # Logo referenced in package metadata
};
```

## Terminal ASCII Art

For terminal display, consider creating an ASCII/Unicode art version:

```
 _              
| |_ _ __ _   _ 
| __| '__| | | |
| |_| |  | |_| |
 \__|_|   \__, |
          |___/ 
```

This can be displayed in:
- `try --help` output
- Welcome messages
- Error screens
- Documentation

## Current Status

**Logo Status:** 🎨 Design concepts under review

See [LOGO_CONCEPTS.md](../LOGO_CONCEPTS.md) for proposed designs and community discussion.

## Questions?

For questions about logo usage or to submit designs:
- Open an issue on GitHub
- Reference [Issue #26](https://github.com/tobi/try/issues/26) for design discussion
- Follow the contribution guidelines above

---

*Your experiments deserve a home.* 🏠
