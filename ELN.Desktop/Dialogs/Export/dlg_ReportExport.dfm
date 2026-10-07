object dlgReportExport: TdlgReportExport
  Left = 0
  Top = 0
  Caption = 'Export Report'
  ClientHeight = 560
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  OnShow = FormShow
  TextHeight = 13
  object spMain: TSplitter
    Left = 260
    Top = 0
    Width = 5
    Height = 515
    ExplicitHeight = 560
  end
  object pnlLeft: TRzPanel
    Left = 0
    Top = 0
    Width = 260
    Height = 515
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblItems: TLabel
      Left = 12
      Top = 8
      Width = 86
      Height = 13
      Caption = 'Items to include:'
    end
    object clbItems: TCheckListBox
      Left = 12
      Top = 26
      Width = 236
      Height = 170
      ItemHeight = 13
      TabOrder = 0
    end
    object gbSections: TGroupBox
      Left = 12
      Top = 204
      Width = 236
      Height = 180
      Caption = ' Sections '
      TabOrder = 1
      object chkMetadata: TCheckBox
        Left = 14
        Top = 22
        Width = 200
        Height = 17
        Caption = '  Metadata'
        Checked = True
        State = cbChecked
        TabOrder = 0
      end
      object chkProtocols: TCheckBox
        Left = 14
        Top = 44
        Width = 200
        Height = 17
        Caption = '  Protocols'
        Checked = True
        State = cbChecked
        TabOrder = 1
      end
      object chkValues: TCheckBox
        Left = 14
        Top = 66
        Width = 200
        Height = 17
        Caption = '  Values'
        Checked = True
        State = cbChecked
        TabOrder = 2
      end
      object chkFiles: TCheckBox
        Left = 14
        Top = 88
        Width = 200
        Height = 17
        Caption = '  Files'
        Checked = True
        State = cbChecked
        TabOrder = 3
      end
      object chkTags: TCheckBox
        Left = 14
        Top = 110
        Width = 200
        Height = 17
        Caption = '  Tags'
        Checked = True
        State = cbChecked
        TabOrder = 4
      end
      object chkComments: TCheckBox
        Left = 14
        Top = 132
        Width = 200
        Height = 17
        Caption = '  Comments'
        Checked = True
        State = cbChecked
        TabOrder = 5
      end
      object chkSignatures: TCheckBox
        Left = 14
        Top = 154
        Width = 200
        Height = 17
        Caption = '  Signatures'
        Checked = True
        State = cbChecked
        TabOrder = 6
      end
    end
    object rgPaper: TRadioGroup
      Left = 12
      Top = 392
      Width = 236
      Height = 54
      Caption = ' Paper Size '
      Columns = 2
      ItemIndex = 0
      Items.Strings = (
        'A4'
        'Letter')
      TabOrder = 2
    end
    object lblPath: TLabel
      Left = 12
      Top = 454
      Width = 61
      Height = 13
      Caption = 'Output path:'
    end
    object edtPath: TRzEdit
      Left = 12
      Top = 472
      Width = 170
      Height = 21
      Text = ''
      TabOrder = 3
    end
    object btnBrowse: TRzButton
      Left = 188
      Top = 469
      Width = 60
      Caption = 'Browse...'
      TabOrder = 4
      OnClick = btnBrowseClick
    end
  end
  object pnlRight: TRzPanel
    Left = 265
    Top = 0
    Width = 635
    Height = 515
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 515
    Width = 900
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 2
    Color = clBtnFace
    object btnPreview: TRzButton
      Left = 644
      Top = 10
      Caption = 'Preview'
      TabOrder = 0
      OnClick = btnPreviewClick
    end
    object btnExport: TRzButton
      Left = 730
      Top = 10
      Caption = 'Export PDF'
      TabOrder = 1
      OnClick = btnExportClick
    end
    object btnCancel: TRzButton
      Left = 816
      Top = 10
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 2
    end
  end
  object SaveDialog: TSaveDialog
    DefaultExt = '.pdf'
    Filter = 'PDF Files (*.pdf)|*.pdf|All Files (*.*)|*.*'
    Title = 'Export Report as PDF'
    Left = 600
    Top = 16
  end
end
