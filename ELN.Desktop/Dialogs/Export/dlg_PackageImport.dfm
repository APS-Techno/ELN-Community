object dlgPackageImport: TdlgPackageImport
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Import Package'
  ClientHeight = 250
  ClientWidth = 345
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 13
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 345
    Height = 205
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblFile: TLabel
      Left = 16
      Top = 10
      Width = 61
      Height = 13
      Caption = 'Package file:'
    end
    object lblPreview: TLabel
      Left = 16
      Top = 55
      Width = 85
      Height = 13
      Caption = 'Package preview:'
    end
    object edtFile: TRzEdit
      Left = 16
      Top = 28
      Width = 240
      Height = 21
      Text = ''
      Color = clInfoBk
      ReadOnly = True
      TabOrder = 0
    end
    object btnBrowse: TRzButton
      Left = 264
      Top = 25
      Width = 70
      Caption = 'Browse...'
      TabOrder = 1
      OnClick = btnBrowseClick
    end
    object mmoPreview: TMemo
      Left = 16
      Top = 73
      Width = 318
      Height = 120
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 2
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 205
    Width = 345
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnImport: TRzButton
      Left = 184
      Top = 10
      Caption = 'Import'
      TabOrder = 0
      OnClick = btnImportClick
    end
    object btnCancel: TRzButton
      Left = 265
      Top = 10
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object OpenDialog: TOpenDialog
    DefaultExt = '.elnpkg'
    Filter = 'ELN Package (*.elnpkg)|*.elnpkg|All Files (*.*)|*.*'
    Title = 'Select Package'
    Left = 600
    Top = 16
  end
end
