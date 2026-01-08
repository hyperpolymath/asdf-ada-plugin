;; SPDX-License-Identifier: AGPL-3.0-or-later
;; ECOSYSTEM.scm - Project ecosystem positioning

(ecosystem
  (version "1.0.0")
  (name "asdf-ada-plugin")
  (type "asdf-plugin")
  (purpose "Version management for Ada/GNAT compiler")

  (position-in-ecosystem
    (category "developer-tools")
    (subcategory "version-management")
    (layer "user-facing"))

  (related-projects
    (sibling-standard
      (name "asdf")
      (relationship "plugin-host")
      (url "https://asdf-vm.com"))
    (sibling-standard
      (name "ada")
      (relationship "managed-tool")
      (url "https://github.com/alire-project/GNAT-FSF-builds")))

  (what-this-is
    "An asdf plugin for managing Ada/GNAT compiler versions")

  (what-this-is-not
    "Not a standalone version manager"
    "Not a replacement for the tool itself"))
