object ELNRecipeViewerPlugin: TELNRecipeViewerPlugin
  OnCreate = upfVisualPluginCreate
  OnDestroy = upfVisualPluginDestroy
  PluginID = '7071'
  PluginName = 'Recipe Viewer'
  Author = 'APS Technology'
  Description = 'Deposition recipe (.rcpx) viewer'
  Commands = <>
  Version = '6.13.0'
  Height = 590
  Width = 839
  PixelsPerInch = 192
end
