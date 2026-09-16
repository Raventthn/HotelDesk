USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CapNhatGiaLoaiPhong
    @MaLoai VARCHAR(10),
    @GiaCoBan DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @MaLoai = NULLIF(LTRIM(RTRIM(@MaLoai)), '');

    IF @MaLoai IS NULL
        THROW 51705, N'Mã loại phòng không được để trống.', 1;
    IF @GiaCoBan IS NULL OR @GiaCoBan < 0
        THROW 51706, N'Giá cơ bản không được âm.', 1;

    UPDATE dbo.LOAIPHONG
    SET GiaCoBan = @GiaCoBan
    WHERE MaLoai = @MaLoai;

    IF @@ROWCOUNT <> 1
        THROW 51707, N'Loại phòng không tồn tại.', 1;

    SELECT MaLoai, TenLoai, GiaCoBan, N'Cập nhật giá phòng thành công.' AS ThongBao
    FROM dbo.LOAIPHONG
    WHERE MaLoai = @MaLoai;
END;
GO
