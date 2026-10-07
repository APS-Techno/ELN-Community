object dlgPackageExport: TdlgPackageExport
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Export Package'
  ClientHeight = 300
  ClientWidth = 350
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
    Width = 350
    Height = 255
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblItems: TLabel
      Left = 16
      Top = 10
      Width = 79
      Height = 13
      Caption = 'Items to export:'
    end
    object lblPath: TLabel
      Left = 16
      Top = 180
      Width = 61
      Height = 13
      Caption = 'Export path:'
    end
    object clbItems: TCheckListBox
      Left = 16
      Top = 28
      Width = 318
      Height = 140
      ItemHeight = 13
      TabOrder = 0
    end
    object edtPath: TRzEdit
      Left = 16
      Top = 198
      Width = 240
      Height = 21
      Text = ''
      TabOrder = 1
    end
    object btnBrowse: TRzButton
      Left = 264
      Top = 195
      Width = 70
      Caption = 'Browse...'
      TabOrder = 2
      OnClick = btnBrowseClick
    end
    object chkIncludeFiles: TCheckBox
      Left = 16
      Top = 225
      Width = 150
      Height = 14
      Caption = '  Include files'
      Checked = True
      State = cbChecked
      TabOrder = 3
    end
    object chkIncludeHistory: TCheckBox
      Left = 175
      Top = 225
      Width = 150
      Height = 14
      Caption = '  Include status history'
      Checked = True
      State = cbChecked
      TabOrder = 4
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 255
    Width = 350
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnExport: TRzButton
      Left = 184
      Top = 10
      Caption = 'Export'
      TabOrder = 0
      OnClick = btnExportClick
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
  object SaveDialog: TSaveDialog
    DefaultExt = '.elnpkg'
    Filter = 'ELN Package (*.elnpkg)|*.elnpkg|All Files (*.*)|*.*'
    Title = 'Export Package'
    Left = 600
    Top = 16
  end
end
