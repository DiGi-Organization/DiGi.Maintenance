# Licences - Data and Software

Terms of reuse for every external data source and third-party component of the DiGi GIS system, the licence of
the DiGi repositories, and the decisions that follow from them (DiGi-Organization/DiGi.Maintenance#17).
Written for the publication series *Publikacje GIS* (papers 03, 10 and 11) and for any future commercial step.

> [!IMPORTANT]
> This is an engineering record, not legal advice. Before any commercial release, have the decisions in §4 reviewed.

| Field | Value |
|---|---|
| Checked | 2026-10-23 |
| Current use | open source (GPL-3.0), public repositories, non-commercial; commercial use of some parts is not planned but not excluded |
| Open items | §5 |
| EPW source | energyplus.net weather pages (confirmed by the maintainer, 2026-10-23) |

## 1. DiGi repositories

All 74 repositories of DiGi-Organization carry **GPL-3.0** (`LICENSE` on the default branch, checked through
`GET repos/DiGi-Organization/<repo>/license`); 73 are public, `DiGi.Temp` is private. `gh repo list` shows an
empty licence field for every repository - read the per-repository endpoint instead.

## 2. Data sources

| Item | Provider | Licence / terms | URL | Checked | Obligations |
|---|---|---|---|---|---|
| BDOT10k (buildings, settlements, units, roads) | GUGiK | free of charge, no licence issued - Geodetic and Cartographic Law (Dz.U. 2024 poz. 1151) art. 40a(2)(1)(h), art. 40c(5) | [geoportal.gov.pl](https://www.geoportal.gov.pl/) | 2026-10-23 | name the source in publications (art. 40c(3)) |
| PRG (unit boundaries, address points) | GUGiK | as above - art. 40a(2)(1)(a) | as above | 2026-10-23 | as above |
| Orthophoto (WMS `StandardResolutionTime`) | GUGiK | as above - art. 40a(2)(1)(e) | [ORTO WMS](https://mapy.geoportal.gov.pl/wss/service/PZGIK/ORTO/WMS/StandardResolutionTime) | 2026-10-23 | as above |
| Terrain model (`GetHByXY`) | GUGiK | as above - art. 40a(2)(1)(d) | [geoportal.gov.pl](https://www.geoportal.gov.pl/) | 2026-10-23 | as above |
| Budynki3D, CityGML LoD1/LoD2 | GUGiK | published free of charge on the Geoportal; **not named** in art. 40a(2)(1). Closest bases: (1)(j) building identifiers, geometry and type, and (2)(b) free provision for scientific research | [modele 3D budynków](https://www.geoportal.gov.pl/pl/dane/inne-dane/modele-3d-budynkow/) | 2026-10-23 | name the source; for commercial use confirm the terms with GUGiK (§5) |
| Local Data Bank (BDL API) | GUS | CC BY 4.0 | [bdl.stat.gov.pl](https://bdl.stat.gov.pl/) | 2026-10-22 | attribution |
| NSP 2021 population in a 1 km grid | GUS (Geostatistics Portal, INSPIRE ATOM) | portal terms: access "public and free of charge"; no licence or attribution clause named | [portal.geo.stat.gov.pl](https://portal.geo.stat.gov.pl/en/terms-and-conditions/) | 2026-10-23 | name GUS as the source |
| Typical meteorological years 1971–2000 (TLM1970) | ministry responsible for construction | **CC0 1.0** (dane.gov.pl dataset 797, modified 2024-03-19) | [dane.gov.pl/dataset/797](https://dane.gov.pl/en/dataset/797) | 2026-10-23 | none (citation good practice) |
| Typical meteorological years 2001–2020 (TLM2000) | P. Narowski, Warsaw University of Technology | freeware: free use and free redistribution for research, design and building-energy analysis, **unmodified only**; no sale or modification; commercial software or paid information services need the author's **written consent**; publications must cite the TLM2000 papers | [licence](http://fizyka-budowli.pl/license-caveat-emptor/) | 2026-10-23 | cite Narowski 2022 (*Instal* 10/2022, DOI 10.36119/15.2022.10.2; *COW* 9/2022, DOI 10.15199/9.2022.9.1) |
| EPW files in `epw_file` - IMGW family (`*_IMGW.epw`) | downloaded from the EnergyPlus weather pages (energyplus.net, Europe WMO region 6, Poland; the page has since been removed, the files are now hosted by Climate.OneBuilding.Org); derived from the ministry's 1971–2000 typical years | source data **CC0 1.0** (dane.gov.pl dataset 797); the EPW conversion carries no separate licence | [climate.onebuilding.org](https://climate.onebuilding.org/WMO_Region_6_Europe/POL_Poland/index.html) | 2026-10-23 | none (citation good practice) |
| EPW files in `epw_file` - IWEC family (`*_IWEC.epw`) | same download; ASHRAE International Weather for Energy Calculations | **(c) 2001 ASHRAE, all rights reserved** "as noted in the License Agreement and Additional Conditions" (COMMENTS 1 line of every IWEC file) | [ashrae.org](https://www.ashrae.org/) | 2026-10-23 | use for calculations; **do not redistribute the files**; results computed from them may be published with the source named |
| Building regulations (U-value limits) | Journal of Laws | public law, not protected by copyright | [isap.sejm.gov.pl](https://isap.sejm.gov.pl/) | 2026-10-22 | none |

## 3. Third-party software

Licences read from NuGet metadata, the projects' `LICENSE` files and PyPI / Hugging Face on 2026-10-23.

| Component | Used in | Licence | Note |
|---|---|---|---|
| **ultralytics** 8.4 (YOLO training, export) and the YOLO base weights | `DiGi.YOLO` (training and export scripts), `DiGi.GIS.YOLO.UI`, `DiGi.YOLO.ONNX` (runs the exported model) | **AGPL-3.0** | Ultralytics treats trained models as covered too - see §4 |
| **Emgu.CV** 4.12 (+ `runtime.windows`) | `DiGi.Emgu.CV`, `DiGi.GIS.Emgu.CV`, `DiGi.GIS.IO` (deployed API) | **GPL-3.0 or commercial** (dual) | see §4 |
| SolarCalculator 3.6 | `DiGi.Solar` (sun position) | LGPL-3.0-or-later | linked as a separate assembly |
| ProjNET4GeoAPI 1.4 | coordinate transformation | LGPL-2.1 | linked as a separate assembly |
| Grasshopper / RhinoCommon | `*.Rhino` plug-ins | McNeel SDK terms; Rhino licence per user | not part of the server |
| Microsoft.ML 5.0, ML.LightGbm, ML.OneDal | `DiGi.GIS.ML` | MIT | |
| Microsoft.ML.OnnxRuntime 1.29 | `DiGi.YOLO.ONNX` (inference) | MIT | |
| Laya 0.4 (Python) and its model | `DiGi.Laya` | Apache-2.0 (package and Hugging Face model) | |
| PyTorch, ONNX, onnxslim (Python) | training / export | BSD-3-Clause, Apache-2.0, MIT | |
| ComputeSharp 3.2 | `DiGi.ComputeSharp`, `DiGi.Solar` (GPU) | MIT | |
| NetTopologySuite 2.6 | geometry | BSD-3-Clause | |
| Npgsql 10.0 | PostgreSQL access | PostgreSQL licence | |
| MathNet.Numerics 5.0, SharpGLTF.Toolkit 1.0, Newtonsoft.Json 13, OsmSharp 6.2, Plotly.NET 3.0, LiveCharts.Wpf.Core 0.9, LibGit2Sharp 0.31, Swashbuckle.AspNetCore 10.2, Microsoft.* / System.* | various | MIT | |
| QuikGraph 2.5 | graphs | MS-PL | |
| IronPython 3.4, Serilog sinks/extensions | scripting, logging | Apache-2.0 | |
| three.js 0.170, three-mesh-bvh 0.8 (CDN) | `DiGi.GIS.WebAPI.UI` viewer | MIT | |
| xunit, Xunit.SkippableFact, coverlet, Microsoft.NET.Test.Sdk | tests only | Apache-2.0, MS-PL, MIT | not distributed |

## 4. Decisions

### 4.1 Now: open source, non-commercial

- **Emgu.CV** is used under its **GPL-3.0** option. DiGi is GPL-3.0 and public, which satisfies it; no commercial licence is needed.
- **ultralytics** and the trained detector are used under **AGPL-3.0**. GPL-3.0 code may be combined with AGPL-3.0 code (GPL-3.0 §13). Training scripts and `model.pt` / the ONNX export are published under AGPL-3.0. Because the deployed portal runs the detector for users over the network, the portal states where the source is (the public GitHub repositories) - the AGPL network clause.
- **TLM2000** is used for research only and redistributed, if at all, unmodified with the citation.
- **Weather files** of unclear terms (IWEC-derived) are referenced, not redistributed.

### 4.2 If a part becomes commercial

What changes depends on the form:

| Form | GPL-3.0 code incl. Emgu.CV (GPL) | ultralytics / detector (AGPL) | TLM2000 | Geodetic data |
|---|---|---|---|---|
| **Paid web service** (nothing distributed to the customer) | no obligation beyond the licence: GPL is triggered by distribution, not by network use | source of the AGPL parts must be offered to the service's users - or buy an **Ultralytics Enterprise** licence, or retrain on an Apache-2.0 detector (e.g. RT-DETR, D-FINE) | **written consent** of the author | free, attribution; Budynki3D terms to confirm (§5) |
| **Distributed closed software** (desktop / tray application sold) | own code: the copyright holder may dual-license it; Emgu.CV: **commercial licence** or replace with an Apache-2.0 binding (e.g. OpenCvSharp); LGPL parts (SolarCalculator, ProjNET) stay separate replaceable assemblies | as above | as above | as above |

Keeping image processing behind `DiGi.Emgu.CV` / `DiGi.GIS.Emgu.CV` and inference behind `DiGi.YOLO.ONNX` keeps both replaceable without touching the rest of the system.

## 5. Open items

1. **Licence of the derived data release** (paper 11: occupancy, first-appearance year, envelope areas, irradiation) - recommended **CC BY 4.0**, consistent with the GUS terms and the attribution duty of the geodetic law. *Decision pending.*
2. **IWEC sample file in public repositories** - `POL_Warsaw.123750_IWEC.epw` is committed in `DiGi.EPW/documentation/samples` and `DiGi.Test/files`; it is ASHRAE-copyrighted. Replace it with an IMGW-family file (CC0 source) and remove it. *Decision pending.*
3. **Budynki3D legal basis** - before a commercial use, ask GUGiK which provision of art. 40a covers the models.
