USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_TaoKhachHangTuThongTin
    @HoTen NVARCHAR(200),
    @SDT VARCHAR(15),
    @CCCD VARCHAR(20),
    @Email VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @HoTen = NULLIF(LTRIM(RTRIM(@HoTen)), N'');
    SET @SDT = NULLIF(LTRIM(RTRIM(@SDT)), '');
    SET @CCCD = NULLIF(LTRIM(RTRIM(@CCCD)), '');
    SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');

    IF @HoTen IS NULL OR DATALENGTH(@HoTen) > 200
        THROW 51202, N'Họ tên không được để trống và tối đa 100 ký tự.', 1;
    IF @SDT IS NULL OR DATALENGTH(@SDT) > 15
        THROW 51203, N'Số điện thoại không được để trống và tối đa 15 ký tự.', 1;
    IF @CCCD IS NULL OR DATALENGTH(@CCCD) > 20
        THROW 51204, N'CCCD không được để trống và tối đa 20 ký tự.', 1;
    IF @Email IS NOT NULL AND DATALENGTH(@Email) > 100
        THROW 51205, N'Email tối đa 100 ký tự; có thể để trống.', 1;

    DECLARE @MaKH VARCHAR(10);
    WHILE @MaKH IS NULL
       OR EXISTS (SELECT 1 FROM dbo.KHACHHANG WITH (UPDLOCK, HOLDLOCK) WHERE MaKH = @MaKH)
    BEGIN
        SET @MaKH = CONCAT('KH', RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), NEXT VALUE FOR dbo.Seq_MaKhachHang)), 8));
    END;

    INSERT dbo.KHACHHANG(MaKH, HoTen, SDT, Email, CCCD)
    VALUES (@MaKH, @HoTen, @SDT, @Email, @CCCD);

    SELECT @MaKH AS MaKH, @HoTen AS HoTen, N'Tạo khách hàng thành công.' AS ThongBao;
END;
GO
