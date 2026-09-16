USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ThemLoaiPhong
    @MaLoai VARCHAR(10),
    @TenLoai NVARCHAR(50),
    @GiaCoBan DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @MaLoai = NULLIF(LTRIM(RTRIM(@MaLoai)), '');
    SET @TenLoai = NULLIF(LTRIM(RTRIM(@TenLoai)), N'');

    IF @MaLoai IS NULL OR @TenLoai IS NULL
        THROW 51701, N'Mã và tên loại phòng không được để trống.', 1;
    IF @MaLoai COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%'
        THROW 51702, N'Mã loại phòng chỉ được chứa chữ, số, dấu - hoặc _.', 1;
    IF @GiaCoBan IS NULL OR @GiaCoBan < 0
        THROW 51703, N'Giá cơ bản không được âm.', 1;

    BEGIN TRY
        INSERT dbo.LOAIPHONG(MaLoai, TenLoai, GiaCoBan)
        VALUES (@MaLoai, @TenLoai, @GiaCoBan);

        SELECT MaLoai, TenLoai, GiaCoBan, N'Thêm loại phòng thành công.' AS ThongBao
        FROM dbo.LOAIPHONG
        WHERE MaLoai = @MaLoai;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 51704, N'Mã loại phòng đã tồn tại.', 1;
        THROW;
    END CATCH;
END;
GO
