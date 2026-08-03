# Project path navigation and compact thread controls

**Date:** 2026-08-03

**Action:** Replaced the raw page-name header with query-free project/path navigation, added current/all-project switching and path-prefix project filtering, compacted annotation actions into one row with a full-width unboxed reply composer, removed redundant page edit/delete actions, and made final-version deletion remove the empty page.

**Decision:** Stored captured paths retain their full identity, including query state, while review navigation presents only route hierarchy. Human-readable names, including URI punctuation, remain literal. Page lifecycle is owned by screenshot versions: a page persists while any version remains and is removed with the last version.
