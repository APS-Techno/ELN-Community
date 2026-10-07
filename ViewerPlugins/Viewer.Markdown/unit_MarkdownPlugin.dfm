object ELNMarkdownViewerPlugin: TELNMarkdownViewerPlugin
  OnCreate = upfVisualPluginCreate
  OnDestroy = upfVisualPluginDestroy
  PluginID = '7026'
  PluginName = 'Markdown Viewer'
  Description = 'Markdown File Viewer (CommonMark + GFM + KaTeX)'
  Commands = <>
  Version = '1.0.0'
  Height = 590
  Width = 839
  PixelsPerInch = 192
end
