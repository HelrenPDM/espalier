# SCORM schema files

A SCORM package carries the XML schema files of its version at its root, next
to `imsmanifest.xml`. The SCORM 2004 4th edition Content Aggregation Model
(CAM 3.2) states: "The imsmanifest.xml and any of its supporting control files
(e.g., DTD, XSD) shall be at the root of the content package."

This repository does not hold these files. `mix espalier.scorm_xsd` (also run
by `make scorm-xsd`, `make setup`, `make e2e` and the builder stage of the
Dockerfile) fetches them into `priv/scorm/xsd/12/` and `priv/scorm/xsd/2004/`,
which git ignores, and `Espalier.Interop.ExportWorker` copies the files of a
version into every package of that version. `Espalier.Interop.SchemaFiles`
pins each archive and each file by SHA-256, so a changed download fails the
fetch and reaches no package.

## Sources

Retrieved on 2026-10-12. Both archives come from the schema definition files
that Rustici Software publishes on scorm.com.

| Version | Archive | SHA-256 of the archive | Files |
|---|---|---|---|
| SCORM 1.2 | <https://scorm.com/wp-content/assets/SchemaDefinitionFiles/zips/scorm12schemadefinition.zip> | `728d26a798de0e4c48cf2dd8e08b1037eb9e70d4f8c9d63221f5c4edc7f5338a` | `adlcp_rootv1p2.xsd`, `imscp_rootv1p1p2.xsd`, `imsmd_rootv1p2p1.xsd`, `ims_xml.xsd` |
| SCORM 2004 4th edition | <https://scorm.com/wp-content/assets/SchemaDefinitionFiles/zips/scorm20044theditionschemadefinition%28nometadata%29.zip> | `81ddd45740a7915e9927bc525cc2b6cd3f92e3119f7133c45fa1f2d8ec072ee6` | `adlcp_v1p3.xsd`, `adlnav_v1p3.xsd`, `adlseq_v1p3.xsd`, `imscp_v1p1.xsd`, `imsss_v1p0.xsd` with its nine parts (`auxresource`, `control`, `delivery`, `limit`, `objective`, `random`, `rollup`, `seqrule`, `util`), `xml.xsd`, `XMLSchema.dtd`, `datatypes.dtd` |

The archives also hold an `imsmanifest.xml` template, which the fetch leaves
out. The SHA-256 of every file is pinned in `Espalier.Interop.SchemaFiles`.

The SCORM 1.2 files are byte-identical to those in the content package
examples that ADL published with SCORM 1.2. The ADL files of SCORM 2004
(`adlcp_v1p3.xsd`, `adlnav_v1p3.xsd`, `adlseq_v1p3.xsd`) and the IMS Simple
Sequencing files are byte-identical to the per-schema archives of ADL.
Rustici changed one line of `imscp_v1p1.xsd`: it imports `xml.xsd` from the
package root, where the ADL copy imports `http://www.w3.org/2001/xml.xsd`.
The 2004 set therefore carries `xml.xsd`, the DTD `XMLSchema.dtd` that
`xml.xsd` names in its document type declaration, and `datatypes.dtd`, which
`XMLSchema.dtd` includes.

## License terms

| Files | Holder | Terms | Source of the terms |
|---|---|---|---|
| `adlcp_v1p3.xsd`, `adlnav_v1p3.xsd`, `adlseq_v1p3.xsd` | Advanced Distributed Learning (ADL) | Apache License 2.0 ("Copyright 2014 Advanced Distributed Learning. Licensed under the Apache License, Version 2.0") | README of <https://github.com/adlnet/SCORM-2004-4ed-Test-Suite> at commit `050f1b4282c914154ab80254e4767ce8c58d0d36`, which holds the same files with LF line endings |
| `adlcp_rootv1p2.xsd` | ADL | No license notice. The SCORM 1.2 documents state "© 2001 Advanced Distributed Learning. All Rights Reserved." | SCORM 1.2 Content Aggregation Model |
| `imscp_rootv1p1p2.xsd`, `imsmd_rootv1p2p1.xsd`, `ims_xml.xsd`, `imscp_v1p1.xsd` | IMS Global Learning Consortium, now 1EdTech | The files carry "Copyright (c) 2001 IMS GLC, Inc." and no grant. 1EdTech states: "Any individual or organization can distribute 1EdTech documents as is." It grants no automatic right to distribute derivatives. The copies on imsglobal.org carry a 2007 notice that asks distributors to register with IMS. | <https://www.1edtech.org/policy/how-to-use-1edtech-documents>, <https://www.1edtech.org/standards/specification-license> |
| `imsss_v1p0*.xsd` | IMS Global Learning Consortium, now 1EdTech | As above. The files match the copies on imsglobal.org except for the notice block. | As above |
| `xml.xsd`, `XMLSchema.dtd`, `datatypes.dtd` | World Wide Web Consortium | W3C Software and Document License: "Permission to copy, modify, and distribute this work, with or without modification, for any purpose and without fee or royalty is hereby granted", with the notice on all copies. Copyright © World Wide Web Consortium. | <https://www.w3.org/copyright/software-license-2023/> |

The IMS files and `adlcp_rootv1p2.xsd` have no grant that clearly covers
redistribution in an open-source repository. The project therefore keeps
them out of the repository and out of its source distribution. An
organization that runs Espalier fetches them when it builds the release, and
its SCORM packages carry them unmodified, as every SCORM package does. The
Rustici site states that its content is licensed under Creative Commons
Attribution 3.0, which covers the changed import line of `imscp_v1p1.xsd`.
