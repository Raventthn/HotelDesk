USE QL_KhachSan;
GO
-- Isolated fixtures. RunId prevents simultaneous demonstrations from sharing data.
IF OBJECT_ID(N'dbo.DEMO_BookingRace_Run',N'U') IS NULL
    CREATE TABLE dbo.DEMO_BookingRace_Run(
        RunId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
IF OBJECT_ID(N'dbo.DEMO_BookingRace_Request',N'U') IS NULL
    CREATE TABLE dbo.DEMO_BookingRace_Request(
        RunId UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.DEMO_BookingRace_Run(RunId),
        Actor CHAR(1) NOT NULL CHECK(Actor IN('A','B')),
        CheckedFree BIT NOT NULL DEFAULT 0,
        ReportedSuccess BIT NOT NULL DEFAULT 0,
        SessionId INT NULL,
        PRIMARY KEY(RunId,Actor));
IF OBJECT_ID(N'dbo.DEMO_BookingRace_Night',N'U') IS NULL
    CREATE TABLE dbo.DEMO_BookingRace_Night(
        RunId UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.DEMO_BookingRace_Run(RunId),
        MaPhong VARCHAR(10) NOT NULL,
        Ngay DATE NOT NULL,
        OwnerActor CHAR(1) NULL CHECK(OwnerActor IN('A','B')),
        PRIMARY KEY(RunId,MaPhong,Ngay));
GO
