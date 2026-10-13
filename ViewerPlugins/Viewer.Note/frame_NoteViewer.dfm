object frmNoteViewer: TfrmNoteViewer
  Left = 0
  Top = 0
  Width = 1343
  Height = 1013
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  TabOrder = 0
  PixelsPerInch = 192
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 1331
    Height = 82
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alTop
    BevelWidth = 2
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = 15987699
    object lblLogTitle: TRzLabel
      AlignWithMargins = True
      Left = 8
      Top = 12
      Width = 172
      Height = 51
      Margins.Left = 6
      Margins.Top = 10
      Margins.Right = 200
      Margins.Bottom = 6
      Align = alLeft
      Caption = 'Note title'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -38
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Transparent = True
    end
  end
  object RichEdit: TRzRichEdit
    AlignWithMargins = True
    Left = 6
    Top = 100
    Width = 1331
    Height = 907
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    Font.Charset = ANSI_CHARSET
    Font.Color = clWindowText
    Font.Height = -32
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
  end
end
