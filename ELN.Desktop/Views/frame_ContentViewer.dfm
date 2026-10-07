object frameContentViewer: TframeContentViewer
  Left = 0
  Top = 0
  Width = 605
  Height = 662
  TabOrder = 0
  object Cards: TCardPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 599
    Height = 609
    Align = alClient
    ActiveCard = Card1
    BevelOuter = bvNone
    Caption = 'Cards'
    TabOrder = 0
    object Card1: TCard
      Left = 0
      Top = 0
      Width = 599
      Height = 609
      Caption = 'Card1'
      CardIndex = 0
      TabOrder = 0
      ExplicitWidth = 185
      ExplicitHeight = 41
      object pnlDownload: TPanel
        AlignWithMargins = True
        Left = 5
        Top = 536
        Width = 589
        Height = 68
        Margins.Left = 5
        Margins.Top = 5
        Margins.Right = 5
        Margins.Bottom = 5
        Align = alBottom
        BevelOuter = bvNone
        TabOrder = 0
        Visible = False
        object lblDownload: TLabel
          AlignWithMargins = True
          Left = 16
          Top = 16
          Width = 557
          Height = 17
          Margins.Left = 16
          Margins.Top = 16
          Margins.Right = 16
          Margins.Bottom = 8
          Align = alTop
          Caption = 'Downloading...'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -13
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          ExplicitWidth = 86
        end
        object barDownload: TProgressBar
          AlignWithMargins = True
          Left = 16
          Top = 41
          Width = 557
          Height = 23
          Margins.Left = 16
          Margins.Top = 0
          Margins.Right = 16
          Margins.Bottom = 0
          Align = alTop
          TabOrder = 0
        end
      end
    end
    object HypothesesCard: TCard
      Left = 0
      Top = 0
      Width = 599
      Height = 609
      Caption = 'HypothesesCard'
      CardIndex = 1
      TabOrder = 1
      inline frmHypotheses: TframeHypotheses
        Left = 0
        Top = 0
        Width = 599
        Height = 609
        Align = alClient
        TabOrder = 0
      end
    end
  end
  object ButtonsPanel: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 618
    Width = 599
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Transparent = True
    Color = clBtnFace
    object btnOpen: TRzBitBtn
      AlignWithMargins = True
      Left = 9
      Top = 8
      Width = 120
      Hint = 'Open file in external application'
      Caption = 'Open'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
      Visible = False
      OnClick = btnOpenClick
      ImageIndex = 27
      Images = dmTreeImages.vilMenuImages
    end
    object btnUpdateFile: TRzBitBtn
      AlignWithMargins = True
      Left = 149
      Top = 8
      Width = 120
      Hint = 'Re-upload edited file to server'
      Caption = 'Update File'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 1
      Visible = False
      OnClick = btnUpdateFileClick
      ImageIndex = 1
      Images = dmTreeImages.vilMenuImages
    end
    object btnUpdatePreview: TRzBitBtn
      AlignWithMargins = True
      Left = 289
      Top = 8
      Width = 120
      Hint = 'Update File Preview'
      Caption = 'Update Preview'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 2
      Visible = False
      OnClick = btnUpdatePreviewClick
      ImageIndex = 12
      Images = dmTreeImages.vilMenuImages
    end
    object btnExtractValues: TRzBitBtn
      AlignWithMargins = True
      Left = 429
      Top = 8
      Width = 120
      Hint = 'Extract values from file'
      Caption = 'Extract Values'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 3
      Visible = False
      OnClick = btnExtractValuesClick
      ImageIndex = 60
      Images = dmTreeImages.vilMenuImages
    end
    object btnResetView: TRzBitBtn
      AlignWithMargins = True
      Left = 559
      Top = 8
      Width = 30
      Hint = 'Reset viewer to default state'
      Caption = ''
      ParentShowHint = False
      ShowHint = True
      TabOrder = 4
      Visible = False
      OnClick = btnResetViewClick
      ImageIndex = 14
      Images = dmTreeImages.vilMenuImages
    end
  end
  object upfPluginManager: TupfPluginManager
    WithConfirm = False
    Extension = 'bpl'
    AppServicesClass = 'TupfStandardApplicationServices'
    OnPackageOnLoadError = upfPluginManagerPackageOnLoadError
    OnPluginRegistered = upfPluginManagerPluginRegistered
    Left = 344
    Top = 320
  end
end
