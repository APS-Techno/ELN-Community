object dlgCommunityPreferences: TdlgCommunityPreferences
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Preferences'
  ClientHeight = 524
  ClientWidth = 680
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object pcPreferences: TPageControl
    Left = 12
    Top = 12
    Width = 656
    Height = 456
    ActivePage = tsGeneral
    TabOrder = 0
    object tsGeneral: TTabSheet
      Caption = 'General'
      object lblTheme: TLabel
        Left = 20
        Top = 24
        Width = 39
        Height = 15
        Caption = 'Theme'
        FocusControl = cmbTheme
      end
      object lblDashboardScale: TLabel
        Left = 20
        Top = 112
        Width = 98
        Height = 15
        Caption = 'Dashboard scale'
        FocusControl = cmbDashboardScale
      end
      object lblPreviewScope: TLabel
        Left = 20
        Top = 200
        Width = 78
        Height = 15
        Caption = 'Preview scope'
        FocusControl = cmbPreviewScope
      end
      object cmbTheme: TComboBox
        Left = 180
        Top = 20
        Width = 320
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object chkDashboard: TCheckBox
        Left = 20
        Top = 68
        Width = 300
        Height = 25
        Caption = 'Show dashboard'
        TabOrder = 1
      end
      object cmbDashboardScale: TComboBox
        Left = 180
        Top = 108
        Width = 160
        Height = 23
        Style = csDropDownList
        TabOrder = 2
        Items.Strings = (
          '80%'
          '100%'
          '120%'
          '150%')
      end
      object chkDarkCharts: TCheckBox
        Left = 20
        Top = 152
        Width = 400
        Height = 25
        Caption = 'Use dark backgrounds for charts'
        TabOrder = 3
      end
      object cmbPreviewScope: TComboBox
        Left = 180
        Top = 196
        Width = 320
        Height = 23
        Style = csDropDownList
        TabOrder = 4
      end
      object chkItemIDs: TCheckBox
        Left = 20
        Top = 240
        Width = 400
        Height = 25
        Caption = 'Show item IDs in the item tree'
        TabOrder = 5
      end
    end
    object tsPaths: TTabSheet
      Caption = 'Directories and reports'
      ImageIndex = 1
      object lblStorage: TLabel
        Left = 20
        Top = 20
        Width = 80
        Height = 15
        Caption = 'Active storage'
        FocusControl = edtStorage
      end
      object lblStorageNote: TLabel
        Left = 20
        Top = 78
        Width = 588
        Height = 30
        AutoSize = False
        Caption = 'This is the active notebook storage directory. Preferences do not move or change it.'
        WordWrap = True
      end
      object lblTemplates: TLabel
        Left = 20
        Top = 126
        Width = 116
        Height = 15
        Caption = 'Templates directory'
        FocusControl = edtTemplates
      end
      object lblPlugins: TLabel
        Left = 20
        Top = 202
        Width = 97
        Height = 15
        Caption = 'Plugins directory'
        FocusControl = edtPlugins
      end
      object lblLogo: TLabel
        Left = 20
        Top = 278
        Width = 67
        Height = 15
        Caption = 'Report logo'
        FocusControl = edtLogo
      end
      object lblPathsNote: TLabel
        Left = 20
        Top = 346
        Width = 588
        Height = 45
        AutoSize = False
        Caption = 'Leave a templates or plugins directory empty to use the application default. Leave the report logo empty for reports without a custom logo.'
        WordWrap = True
      end
      object edtStorage: TEdit
        Left = 20
        Top = 44
        Width = 588
        Height = 23
        ReadOnly = True
        TabOrder = 0
      end
      object edtTemplates: TEdit
        Left = 20
        Top = 150
        Width = 488
        Height = 23
        TabOrder = 1
      end
      object btnTemplates: TButton
        Left = 520
        Top = 148
        Width = 88
        Height = 27
        Caption = 'Browse...'
        TabOrder = 2
        OnClick = BrowseFolderClick
      end
      object edtPlugins: TEdit
        Left = 20
        Top = 226
        Width = 488
        Height = 23
        TabOrder = 3
      end
      object btnPlugins: TButton
        Left = 520
        Top = 224
        Width = 88
        Height = 27
        Caption = 'Browse...'
        TabOrder = 4
        OnClick = BrowseFolderClick
      end
      object edtLogo: TEdit
        Left = 20
        Top = 302
        Width = 488
        Height = 23
        TabOrder = 5
      end
      object btnLogo: TButton
        Left = 520
        Top = 300
        Width = 88
        Height = 27
        Caption = 'Browse...'
        TabOrder = 6
        OnClick = BrowseLogoClick
      end
    end
    object tsTree: TTabSheet
      Caption = 'Tree appearance'
      ImageIndex = 2
      object lblTreeScale: TLabel
        Left = 20
        Top = 24
        Width = 56
        Height = 15
        Caption = 'Tree scale'
        FocusControl = cmbTreeScale
      end
      object lblTreeSpacing: TLabel
        Left = 20
        Top = 64
        Width = 72
        Height = 15
        Caption = 'Row spacing'
        FocusControl = cmbTreeSpacing
      end
      object lblTreeTint: TLabel
        Left = 20
        Top = 104
        Width = 46
        Height = 15
        Caption = 'Row tint'
        FocusControl = cmbTreeTint
      end
      object lblColors: TLabel
        Left = 20
        Top = 148
        Width = 388
        Height = 15
        Caption = 'Named row colors (double-click a color to change it)'
      end
      object cmbTreeScale: TComboBox
        Left = 180
        Top = 20
        Width = 180
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object cmbTreeSpacing: TComboBox
        Left = 180
        Top = 60
        Width = 180
        Height = 23
        Style = csDropDownList
        TabOrder = 1
      end
      object cmbTreeTint: TComboBox
        Left = 180
        Top = 100
        Width = 180
        Height = 23
        Style = csDropDownList
        TabOrder = 2
      end
      object lstColors: TListBox
        Left = 20
        Top = 174
        Width = 460
        Height = 232
        Style = lbOwnerDrawFixed
        ItemHeight = 28
        TabOrder = 3
        OnClick = ColorsClick
        OnDblClick = ColorClick
        OnDrawItem = ColorsDrawItem
      end
      object btnColor: TButton
        Left = 492
        Top = 174
        Width = 116
        Height = 29
        Caption = 'Change...'
        TabOrder = 4
        OnClick = ColorClick
      end
      object btnResetColor: TButton
        Left = 492
        Top = 214
        Width = 116
        Height = 29
        Caption = 'Reset selected'
        TabOrder = 5
        OnClick = ResetColorClick
      end
      object btnResetColors: TButton
        Left = 492
        Top = 254
        Width = 116
        Height = 29
        Caption = 'Reset all colors'
        TabOrder = 6
        OnClick = ResetColorsClick
      end
    end
  end
  object btnOK: TButton
    Left = 472
    Top = 484
    Width = 92
    Height = 28
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 1
  end
  object btnCancel: TButton
    Left = 576
    Top = 484
    Width = 92
    Height = 28
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 2
  end
  object dlgFolder: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Left = 32
    Top = 484
  end
  object dlgLogo: TOpenDialog
    Filter = 'Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|All files (*.*)|*.*'
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Title = 'Select report logo'
    Left = 80
    Top = 484
  end
  object dlgColor: TColorDialog
    Options = [cdFullOpen, cdAnyColor]
    Left = 128
    Top = 484
  end
end
