inherited edLinkTypes: TedLinkTypes
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Link Types'
  ClientHeight = 372
  ClientWidth = 430
  ParentFont = True
  ExplicitWidth = 446
  ExplicitHeight = 411
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 426
    Height = 330
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 426
    ExplicitHeight = 330
    object Label1: TLabel [0]
      Left = 5
      Top = 12
      Width = 47
      Height = 15
      Caption = 'Forward'
    end
    object Label2: TLabel [1]
      Left = 5
      Top = 39
      Width = 44
      Height = 15
      Caption = 'Reverse'
    end
    object Label3: TLabel [2]
      Left = 5
      Top = 66
      Width = 60
      Height = 15
      Caption = 'Description'
    end
    object Label4: TLabel [3]
      Left = 5
      Top = 93
      Width = 52
      Height = 15
      Caption = 'Sort order'
    end
    inherited DBGrid1: TDBGrid
      Left = 4
      Top = 152
      Width = 418
      Height = 174
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Expanded = False
          FieldName = 'ForwardText'
          Title.Caption = 'Forward'
          Width = 110
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'ReverseText'
          Title.Caption = 'Reverse'
          Width = 110
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          Width = 130
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'SortOrder'
          Title.Caption = 'Sort'
          Width = 40
          Visible = True
        end>
    end
    inherited RzDBNavigator1: TRzDBNavigator
      Left = 5
      Top = 121
      Width = 270
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 5
      ExplicitTop = 121
      ExplicitWidth = 270
      ExplicitHeight = 26
    end
    object edForwardText: TDBEdit
      Left = 92
      Top = 9
      Width = 328
      Height = 23
      DataField = 'ForwardText'
      DataSource = DataSource
      TabOrder = 2
    end
    object edReverseText: TDBEdit
      Left = 92
      Top = 36
      Width = 328
      Height = 23
      DataField = 'ReverseText'
      DataSource = DataSource
      TabOrder = 3
    end
    object edDescription: TDBEdit
      Left = 92
      Top = 63
      Width = 328
      Height = 23
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 4
    end
    object edSortOrder: TDBEdit
      Left = 92
      Top = 90
      Width = 80
      Height = 23
      DataField = 'SortOrder'
      DataSource = DataSource
      TabOrder = 5
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 336
    Width = 426
    Height = 34
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 336
    ExplicitWidth = 426
    ExplicitHeight = 34
    inherited btnSave: TBitBtn
      Left = 360
      Top = 5
      Width = 60
      Anchors = [akRight, akBottom]
      ExplicitLeft = 360
      ExplicitTop = 5
      ExplicitWidth = 60
    end
    inherited btnLoadCSV: TBitBtn
      Left = 5
      Top = 3
      Width = 60
      Visible = False
      ExplicitLeft = 5
      ExplicitTop = 3
      ExplicitWidth = 60
    end
  end
  inherited DataSource: TDataSource
    Left = 339
    Top = 227
  end
end
