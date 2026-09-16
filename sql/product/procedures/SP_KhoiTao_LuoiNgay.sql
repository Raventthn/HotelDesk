USE QL_KhachSan;
GO
CREATE OR ALTER PROCEDURE dbo.SP_KhoiTao_LuoiNgay @SoNgayCanSinh INT=30 AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT<>0 THROW 51011,N'Gọi sinh lịch ngoài transaction đang mở.',1;
    SET XACT_ABORT ON;
    IF @SoNgayCanSinh IS NULL OR @SoNgayCanSinh<1 OR @SoNgayCanSinh>366
        THROW 51010,N'@SoNgayCanSinh phải trong khoảng 1–366 và không được NULL.',1;
    DECLARE @HomNay DATE=CONVERT(DATE,GETDATE()), @Khoa INT;
    BEGIN TRY
        BEGIN TRAN;
        EXEC @Khoa=sys.sp_getapplock @Resource=N'HotelDesk.GenerateCalendar',
            @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=15000;
        IF @Khoa<0 THROW 51012,N'Chưa lấy được khóa sinh lịch; thử lại sau.',1;
        ;WITH Dates AS (
            SELECT @HomNay AS Ngay
            UNION ALL SELECT DATEADD(DAY,1,Ngay) FROM Dates
            WHERE Ngay<DATEADD(DAY,@SoNgayCanSinh-1,@HomNay)
        )
        INSERT dbo.PHONG_NGAY(MaPhong,Ngay,MaDatPhong)
        SELECT p.MaPhong,d.Ngay,NULL FROM dbo.PHONG p CROSS JOIN Dates d
        WHERE NOT EXISTS(SELECT 1 FROM dbo.PHONG_NGAY pn WITH(UPDLOCK,HOLDLOCK)
            WHERE pn.MaPhong=p.MaPhong AND pn.Ngay=d.Ngay)
        OPTION(MAXRECURSION 366);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
