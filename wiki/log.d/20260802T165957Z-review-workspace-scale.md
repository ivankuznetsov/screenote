# Make screenshot review large enough to annotate

- Let screenshot review pages use an 1800px content ceiling while retaining
  the global 960px reading width elsewhere.
- Increased the standard 1280px test viewport's annotation canvas from 304px
  to 624px and added browser regression coverage for a 600px minimum.
- Normalized action-button border boxes and made Desktop, Tablet, and Mobile
  switcher segments equal width, with rendered-dimension browser assertions.
