USE QL_KhachSan;
GO

-- Nhận chuỗi rộng hơn cột để kiểm tra độ dài, tránh cắt ngầm tham số đầu vào.
-- MaKH được bảo vệ khỏi trùng lặp bởi primary key, kể cả khi gọi đồng thời.
CREATE OR ALTER PROCEDURE dbo.sp_ThemKhachHang
    @MaKH VARCHAR(MAX),
    @HoTen NVARCHAR(MAX),
    @SDT VARCHAR(MAX),
    @CCCD VARCHAR(MAX),
    @Email VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT <> 0
        THROW 51200, N'Procedure phải được gọi ngoài transaction đang mở.', 1;

    SET XACT_ABORT ON;

    SET @MaKH = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @HoTen = NULLIF(LTRIM(RTRIM(@HoTen)), N'');
    SET @SDT = NULLIF(LTRIM(RTRIM(@SDT)), '');
    SET @CCCD = NULLIF(LTRIM(RTRIM(@CCCD)), '');
    SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');

    IF @MaKH IS NULL OR DATALENGTH(@MaKH) > 10
        OR @MaKH COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%'
        THROW 51201, N'Mã khách hàng phải có 1–10 ký tự chữ, số, - hoặc _.', 1;

    IF @HoTen IS NULL OR DATALENGTH(@HoTen) > 200
        THROW 51202, N'Họ tên không được để trống và tối đa 100 ký tự.', 1;

    IF @SDT IS NULL OR DATALENGTH(@SDT) > 15
        THROW 51203, N'Số điện thoại không được để trống và tối đa 15 ký tự.', 1;

    IF @CCCD IS NULL OR DATALENGTH(@CCCD) > 20
        THROW 51204, N'CCCD không được để trống và tối đa 20 ký tự.', 1;

    IF @Email IS NOT NULL AND DATALENGTH(@Email) > 100
        THROW 51205, N'Email tối đa 100 ký tự; có thể để trống.', 1;

    BEGIN TRY
        -- Một INSERT là nguyên tử; không cần kiểm tra EXISTS trước khi chèn.
        INSERT INTO dbo.KHACHHANG (MaKH, HoTen, SDT, Email, CCCD)
        VALUES (@MaKH, @HoTen, @SDT, @Email, @CCCD);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 51206, N'Mã khách hàng đã tồn tại. Vui lòng dùng mã khác.', 1;
        THROW;
    END CATCH;

    SELECT
        CAST(@MaKH AS VARCHAR(10)) AS MaKH,
        CAST(@HoTen AS NVARCHAR(100)) AS HoTen,
        CAST(@SDT AS VARCHAR(15)) AS SDT,
        CAST(@Email AS VARCHAR(100)) AS Email,
        CAST(@CCCD AS VARCHAR(20)) AS CCCD,
        N'Thêm khách hàng thành công.' AS ThongBao;
END;
GO
