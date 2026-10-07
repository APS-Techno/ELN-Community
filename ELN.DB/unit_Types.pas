unit unit_Types;

interface

type
  TConnectionSettings = record
    Server: string;
    Port: string;
    Database: string;
    User: string;
    Password: string;
    ClientLib: string;
    DriverFolder: string;
  end;

  TSQLiteSettings = record
    Path: string;
    User: string;
    Password: string;
    ClientLib: string;
  end;

implementation

end.
