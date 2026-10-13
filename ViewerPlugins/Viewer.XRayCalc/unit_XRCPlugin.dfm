object XRCViewerPlugin: TXRCViewerPlugin
  OnCreate = upfVisualPluginCreate
  OnDestroy = upfVisualPluginDestroy
  PluginID = '7004'
  PluginName = 'XRCX Viewer'
  Description = 'X-Ray Calc Viewer'
  Commands = <>
  Version = '6.13.0'
  Height = 590
  Width = 839
  PixelsPerInch = 192
end
