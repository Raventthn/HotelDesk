--  Stored Procedure Fix Lost Update
CREATE OR ALTER PROCEDURE dbo.sp_DatPhong_BaoVe
    @MaDatPhong    VARCHAR(10) = NULL,
    @MaKH          VARCHAR(10),
    @MaNV          VARCHAR(10) = 'WEB',
    @NgayNhan      DATE,
    @NgayTra       DATE,
    @DanhSachPhong dbo.DanhSachPhongDat READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaKH = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @MaNV = NULLIF(LTRIM(RTRIM(@MaNV)), '');

    IF @MaKH IS NULL OR @MaNV IS NULL
        THROW 50000, N'Khách hàng và nhân viên không được để trống.', 1;
    IF @NgayNhan IS NULL OR @NgayTra IS NULL OR @NgayTra <= @NgayNhan
        THROW 50001, N'Ngày trả phải sau ngày nhận phòng.', 1;
    IF (SELECT COUNT(*) FROM @DanhSachPhong) <> 1
        THROW 50002, N'Demo chỉ hỗ trợ 1 phòng mỗi lần đặt.', 1;

    DECLARE @MaPhong VARCHAR(10) = (SELECT TOP (1) MaPhong FROM @DanhSachPhong);
    DECLARE @SoDem INT = DATEDIFF(DAY, @NgayNhan, @NgayTra);

    BEGIN TRAN;

    DECLARE @SoNgayConTrong INT;
    SELECT @SoNgayConTrong = COUNT(*)
    FROM dbo.PHONG_NGAY WITH (UPDLOCK, HOLDLOCK)
    WHERE MaPhong = @MaPhong
      AND Ngay >= @NgayNhan AND Ngay < @NgayTra
      AND MaDatPhong IS NULL;

    IF @SoNgayConTrong <> @SoDem
    BEGIN
        ROLLBACK TRAN;
        THROW 50006, N'Phòng đã bị người khác đặt trước trong khoảng thời gian này.', 1;
    END

    WAITFOR DELAY '00:00:03';

    IF @MaDatPhong IS NULL
    BEGIN
        SET @MaDatPhong = CONCAT('BK', RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), NEXT VALUE FOR dbo.Seq_MaDatPhong)), 8));
    END;

    DECLARE @GiaCoBan DECIMAL(18,2), @MaLoai VARCHAR(10), @TenLoai NVARCHAR(50);
    SELECT @GiaCoBan = lp.GiaCoBan, @MaLoai = lp.MaLoai, @TenLoai = lp.TenLoai
    FROM dbo.PHONG p JOIN dbo.LOAIPHONG lp ON lp.MaLoai = p.MaLoai
    WHERE p.MaPhong = @MaPhong;

    DECLARE @TongTien DECIMAL(18,2) = CAST(@GiaCoBan * @SoDem AS DECIMAL(18,2));

    INSERT INTO dbo.DATPHONG (MaDatPhong, MaKH, MaNV, TongTien, TrangThai, Version, NgayNhanDuKien, NgayTraDuKien, SoLuongPhongDat)
    VALUES (@MaDatPhong, @MaKH, @MaNV, @TongTien, N'Đã đặt', 1, @NgayNhan, @NgayTra, 1);

    INSERT INTO dbo.DATPHONG_PHONG (MaDatPhong, MaPhong, MaLoai, TenLoai, DonGia, SoDem, ThanhTien)
    VALUES (@MaDatPhong, @MaPhong, @MaLoai, @TenLoai, @GiaCoBan, @SoDem, @TongTien);

    UPDATE dbo.PHONG_NGAY
    SET MaDatPhong = @MaDatPhong
    WHERE MaPhong = @MaPhong
      AND Ngay >= @NgayNhan AND Ngay < @NgayTra;

    COMMIT TRAN;

    SELECT 
        @MaDatPhong AS MaDatPhong,
        @MaPhong AS MaPhong,
        @TongTien AS TongTien,
        N'Đã đặt' AS TrangThai,
        N'Đặt phòng THÀNH CÔNG (ĐÃ BẢO VỆ). Tránh được Lost Update.' AS ThongBao;
END;
GO