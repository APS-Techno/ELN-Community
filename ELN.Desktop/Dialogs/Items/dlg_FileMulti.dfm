object dlgFileMulti: TdlgFileMulti
  Left = 0
  Top = 0
  Caption = 'Files to attach'
  ClientHeight = 520
  ClientWidth = 800
  Constraints.MinHeight = 400
  Constraints.MinWidth = 640
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 17
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 794
    Height = 461
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lvFiles: TRzListView
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 784
      Height = 305
      Align = alClient
      Columns = <
        item
          Caption = '#'
          Width = 40
        end
        item
          Caption = 'Source filename'
          Width = 245
        end
        item
          Caption = 'Display name'
          Width = 245
        end
        item
          Caption = 'Type'
          Width = 220
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      ShowHint = True
      TabOrder = 0
      ViewStyle = vsReport
      FillLastColumn = False
      OnSelectItem = lvFilesSelectItem
    end
    object pnlType: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 316
      Width = 784
      Height = 44
      Align = alBottom
      BorderOuter = fsFlatRounded
      TabOrder = 1
      object lblType: TRzLabel
        Left = 12
        Top = 13
        Width = 145
        Height = 17
        Caption = 'Selected file type'
      end
      object cbFileType: TRzComboBox
        Left = 164
        Top = 9
        Width = 606
        Height = 25
        Anchors = [akLeft, akTop, akRight]
        Style = csDropDownList
        TabOrder = 0
        OnChange = cbFileTypeChange
      end
    end
    object pnlNaming: TRzPanel
      AlignWithMargins = True
      Left = 5
      Top = 366
      Width = 784
      Height = 90
      Align = alBottom
      BorderOuter = fsFlatRounded
      TabOrder = 2
      object rbOriginalNames: TRzRadioButton
        Left = 12
        Top = 8
        Width = 245
        Height = 20
        Caption = 'Keep display names'
        Checked = True
        TabOrder = 0
        TabStop = True
        OnClick = rbOriginalNamesClick
      end
      object rbPrefixNames: TRzRadioButton
        Left = 12
        Top = 34
        Width = 120
        Height = 20
        Caption = 'Use prefix:'
        TabOrder = 1
        OnClick = rbPrefixNamesClick
      end
      object edPrefix: TRzEdit
        Left = 140
        Top = 31
        Width = 230
        Height = 25
        Text = 'Sample'
        Enabled = False
        TabOrder = 2
        OnChange = edPrefixChange
      end
      object lblPreview: TRzLabel
        Left = 12
        Top = 65
        Width = 756
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        Caption = ''
      end
    end
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 470
    Width = 794
    Height = 47
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object btnSave: TRzBitBtn
      AlignWithMargins = True
      Left = 677
      Top = 4
      Width = 110
      Height = 39
      Margins.Right = 6
      Align = alRight
      Caption = 'Attach'
      Default = True
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object btnCancel: TRzBitBtn
      AlignWithMargins = True
      Left = 581
      Top = 4
      Width = 90
      Height = 39
      Align = alRight
      Caption = 'Cancel'
      Cancel = True
      ModalResult = 2
      TabOrder = 0
    end
    object lblError: TRzLabel
      AlignWithMargins = True
      Left = 9
      Top = 4
      Width = 566
      Height = 39
      Margins.Left = 8
      Align = alClient
      AutoSize = False
      Caption = ''
      Layout = tlCenter
      EllipsisPosition = epPathEllipsis
      ShowHint = True
    end
  end
end
