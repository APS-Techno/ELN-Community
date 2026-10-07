object dlgFile: TdlgFile
  Left = 0
  Top = 0
  Caption = 'Attach files'
  ClientHeight = 620
  ClientWidth = 1000
  Constraints.MinHeight = 450
  Constraints.MinWidth = 760
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 17
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 571
    Width = 994
    Height = 46
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object btnSave: TRzBitBtn
      AlignWithMargins = True
      Left = 867
      Top = 4
      Width = 120
      Height = 38
      Margins.Right = 6
      Align = alRight
      Caption = 'Attach'
      Default = True
      Enabled = False
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object btnCancel: TRzBitBtn
      AlignWithMargins = True
      Left = 771
      Top = 4
      Width = 90
      Height = 38
      Align = alRight
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 0
    end
    object lblStatus: TRzLabel
      AlignWithMargins = True
      Left = 9
      Top = 4
      Width = 756
      Height = 38
      Margins.Left = 8
      Align = alClient
      AutoSize = False
      Caption = 'Select a source file'
      EllipsisPosition = epPathEllipsis
      Layout = tlCenter
      ShowHint = True
    end
  end
  object pnlMetadata: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 419
    Width = 994
    Height = 146
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object pnlFilter: TRzPanel
      AlignWithMargins = True
      Left = 4
      Top = 4
      Width = 986
      Height = 36
      Align = alTop
      BorderOuter = fsFlatRounded
      TabOrder = 0
      object lblFilter: TRzLabel
        AlignWithMargins = True
        Left = 6
        Top = 3
        Width = 88
        Height = 30
        Margins.Left = 6
        Align = alLeft
        AutoSize = False
        Caption = 'Show files'
        Layout = tlCenter
      end
      object cbFilter: TRzComboBox
        AlignWithMargins = True
        Left = 100
        Top = 3
        Width = 883
        Height = 25
        Align = alClient
        Style = csDropDownList
        TabOrder = 0
        OnChange = cbFilterChange
      end
    end
    object lblActionType: TRzLabel
      Left = 12
      Top = 52
      Width = 190
      Height = 17
      Caption = 'Action type (filter context)'
    end
    object lblFileType: TRzLabel
      Left = 242
      Top = 52
      Width = 200
      Height = 17
      Caption = 'Attachment file type'
    end
    object lblName: TRzLabel
      Left = 530
      Top = 52
      Width = 150
      Height = 17
      Caption = 'Display name'
    end
    object cbActionType: TRzComboBox
      Left = 12
      Top = 75
      Width = 216
      Height = 25
      Style = csDropDownList
      TabOrder = 1
      OnChange = cbActionTypeChange
    end
    object cbFileType: TRzComboBox
      Left = 242
      Top = 75
      Width = 274
      Height = 25
      Style = csDropDownList
      Enabled = False
      TabOrder = 2
      OnChange = cbFileTypeChange
    end
    object edName: TRzEdit
      Left = 530
      Top = 75
      Width = 450
      Height = 25
      Anchors = [akLeft, akTop, akRight]
      Text = ''
      Enabled = False
      TabOrder = 3
      OnChange = edNameChange
    end
    object lblMulti: TRzLabel
      Left = 12
      Top = 116
      Width = 968
      Height = 17
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Caption = ''
      Visible = False
    end
  end
  inline Browser: TframeFileSystemBrowser
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 994
    Height = 410
    Align = alClient
    TabOrder = 0
  end
end
