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

## Optional downloaded components

Semantic search and file text extraction use four components that are not in the source tree or the installer. The application downloads them on request into `%LOCALAPPDATA%\APS-ELN\search-artifacts`. It uses a file only after its size and SHA-256 match `ELN.Search/search-artifacts.json`. PDFium and the reranker model are optional parts. The Linux64 search programs (tests and harness; no installed host) use the same models and the Linux archives of ONNX Runtime and PDFium from `ELN.Search/search-artifacts-linux.json`, in `$XDG_DATA_HOME/APS-ELN/search-artifacts` or `~/.local/share/APS-ELN/search-artifacts`, with the same size and SHA-256 check.

| Material | Source | License | Status |
|---|---|---|---|
| ONNX Runtime 1.31.1 (Windows x64) | `onnxruntime-win-x64-1.31.1.zip` from the Microsoft ONNX Runtime GitHub release | MIT | The archive `LICENSE` and `ThirdPartyNotices.txt` are downloaded beside `onnxruntime.dll`. |
| PDFium (Windows x64 build `chromium/8125`) | `pdfium-win-x64.tgz` from the `bblanchon/pdfium-binaries` GitHub release | BSD-3-Clause for PDFium; the bundled libraries are under Apache-2.0, BSD-style, MIT, Zlib and other licenses listed in the archive | `pdfium.dll`, the archive `LICENSE` (MIT, build scripts) and every file in `licenses\` are downloaded beside the DLL. |
| ONNX Runtime 1.31.1 (Linux x64) | `onnxruntime-linux-x64-1.31.1.tgz` from the same Microsoft ONNX Runtime GitHub release | MIT | The archive `LICENSE` and `ThirdPartyNotices.txt` are downloaded beside `libonnxruntime.so.1.31.1`. |
| PDFium (Linux x64 build `chromium/8125`) | `pdfium-linux-x64.tgz` from the same `bblanchon/pdfium-binaries` GitHub release | As for the Windows build; the archive has its own `LICENSE` and the same 18 file names in `licenses/` | `libpdfium.so`, the archive `LICENSE` and every file in `licenses/` are downloaded beside the `lib/` folder. |
| intfloat/multilingual-e5-small, revision `614241f622f53c4eeff9890bdc4f31cfecc418b3` | Hugging Face, ONNX files of that revision | MIT | Model and tokenizer files are downloaded; none are committed or bundled. |
| cross-encoder/mmarco-mMiniLMv2-L12-H384-v1, revision `1427fd652930e4ba29e8149678df786c240d8825` | Hugging Face, file `onnx/model_quint8_avx2.onnx` and `config.json` of that revision | Apache-2.0 (model card). The model was trained on mMARCO (dataset license Apache-2.0), a machine translation of MS MARCO. The MS MARCO terms say the data is for non-commercial research purposes only: https://microsoft.github.io/msmarco/ | Optional. The files are downloaded; none are committed or bundled. |

Legacy private Help, personal user catalogs, private update-feed payloads, deployment history and laboratory/demo records are not selected into this Community tree. Community Help is complete: 19 offline English HTML pages and help.css replace the private manual. This is a source distribution, not a standalone binary package. Official binary distribution still requires applicable publisher permissions and runtime packaging proof.
