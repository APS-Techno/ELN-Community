# Third-party notices and release limits

APS-owned material in this source distribution is licensed under Apache-2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE). The third-party files and assets below retain their original licenses, copyright and attribution. The APS license does not supersede those separate grants.

## Included source and browser assets

| Material | Applicable notice | Status |
|---|---|---|
| Modified Pascal Bcrypt implementation | `Notices/Bcrypt-Unlicense.txt`; embedded grant in `ELN.Model/Bcrypt.pas` | Keep the original Unlicense. The local file identifies version 1.17; it is not certified as an unmodified upstream revision. |
| markdown-it 14.1.0 | `Notices/Markdown/markdown-it-14.1.0-LICENSE.txt` | MIT; retain the full grant and attribution. |
| markdown-it-footnote 4.0.0 | `Notices/Markdown/markdown-it-footnote-4.0.0-LICENSE.txt` | MIT. |
| DOMPurify 3.1.7 | `Notices/Markdown/DOMPurify-3.1.7-LICENSE.txt` | Original Apache-2.0/MPL-2.0 alternative grant retained, independently of the license for APS-owned material. |
| KaTeX 0.16.11 JS/CSS | `Notices/Markdown/KaTeX-0.16.11-LICENSE.txt` | MIT. |
| Distributed KaTeX WOFF2 fonts | `Notices/Markdown/KaTeX-fonts-OFL-1.1.txt` | OFL-1.1; retain each copyright and Reserved Font Name. The font-generation repository's MIT grant is not the distributed-font license. |
| Markdown highlighter | `Notices/SynEdit/MPL-1.1.txt`, `Contributors.txt` and `CHANGES.txt` | Derived from SynHighlighterIni.pas. This separate file uses the MPL-1.1 distribution option and retains the original MPL/GPL alternative grant. |

markdown-it also includes punycode.js, entities, linkify-it, mdurl and uc.micro. Their retained MIT/BSD grants are under `Notices/Markdown`. Only the documented punycode.js 2.3.1 pin is certified from the bundle. The entities and other reference-version filenames identify researched notice references, not exact bundled module revisions. Keep both entities notice references and the mdurl Node/Joyent attribution. Do not infer exact revisions from method markers or publication dates.

The selected fonts are WOFF2. KaTeX CSS also names WOFF/TTF fallbacks that are not in this source selection. Do not invent or download those files as part of this cutover.

## Linked resources

The Community Desktop links its own generated project resource for the application icon, Community version, manifest, and platform metadata. Its icon source is `ELN.Desktop/Assets/DevTools/AppIcons/ELN3_icon.ico`. The retained shared `ELN.Desktop/ELabNotebook3.res` contains no vendor Carbon VCL style. Community uses native Windows styling. Official binary redistribution remains separate from this source release. The separate Commercial resource is unchanged.

## External developer and runtime dependencies

Delphi, TMS Aurelius/BCL, TMS Plugin Framework, KSVC/Raize, TeeChart, SynEdit, VirtualTreeView, JAM ShellBrowser and required toolchain/Indy units remain external. Use valid licensed developer installations. Do not commit their source, DCUs, DCPs, BPLs, license keys or installers.

SQLite and WebView2 are external runtime prerequisites. The retained WebView2 SDK 1.0.3065.39 license and notice text is under `Notices/WebView2-1.0.3065.39`; no loader or runtime binary is included. Those texts do not grant redistribution rights for proprietary runtime BPLs. Exact source-build proof, official binary packaging and publisher entitlements are separate checks.

The Community installer stages selected runtime binaries from explicit local
configuration. It keeps these source notices beside the installed application.
The local build and runtime checks do not certify redistribution rights for
the selected binary versions. Check the applicable runtime grants before
signing or publishing an installer.

Legacy private Help, personal user catalogs, private update-feed payloads, deployment history and laboratory/demo records are not selected into this Community tree. Community Help is complete: 19 offline English HTML pages and help.css replace the private manual. This is a source distribution, not a standalone binary package. Official binary distribution still requires applicable publisher permissions and runtime packaging proof.
