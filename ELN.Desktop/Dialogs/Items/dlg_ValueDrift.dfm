object dlgValueDrift: TdlgValueDrift
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Check Value Sources'
  ClientHeight = 420
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 376
    Width = 894
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object btnClose: TRzBitBtn
      Left = 806
      Top = 8
      Width = 80
      Height = 25
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
  end
  object pnlClient: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 894
    Height = 367
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblSummary: TRzLabel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 884
      Height = 15
      Align = alTop
      Caption = ''
    end
    object lvDrift: TListView
      AlignWithMargins = True
      Left = 5
      Top = 26
      Width = 884
      Height = 336
      Align = alClient
      Columns = <
        item
          Caption = 'Value'
          Width = 55
        end
        item
          Caption = 'Item'
          Width = 150
        end
        item
          Caption = 'File'
          Width = 50
        end
        item
          Caption = 'Key'
          Width = 110
        end
        item
          Caption = 'Differences'
          Width = 150
        end
        item
          Caption = 'Stored'
          Width = 80
        end
        item
          Caption = 'Current'
          Width = 80
        end
        item
          Caption = 'Stored reader'
          Width = 110
        end
        item
          Caption = 'Current reader'
          Width = 110
        end
        item
          Caption = 'Note'
          Width = 150
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
    end
  end
end
