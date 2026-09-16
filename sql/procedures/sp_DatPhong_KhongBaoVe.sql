-- ==========================================
-- sql/procedures/sp_DatPhong_KhongBaoVe.sql
-- (Đã fix lỗi Lost Update, nhận TVP DanhSachPhongDat)
-- ==========================================
USE QL_KhachSan;
GO
CREATE OR ALTER PROCEDURE dbo.sp_DatPhong_KhongBaoVe
    @MaDatPhong    VARCHAR(10) = NULL,
    @MaKH          VARCHAR(10),
    @MaNV          VARCHAR(10) = 'WEB',
    @NgayNhan      DATE,
    @NgayTra       DATE,
    @DanhSachPhong dbo.DanhSachPhongDat READONLY
AS
BEGIN
    SET NOCOUNT ON;

    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaKH = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @MaNV = NULLIF(LTRIM(RTRIM(@MaNV)), '');

    IF @MaKH IS NULL OR @MaNV IS NULL
        THROW 50000, N'Khách hàng và nhân viên không được để trống.', 1;
    IF @NgayNhan IS NULL OR @NgayTra IS NULL OR @NgayTra <= @NgayNhan
        THROW 50001, N'Ngày trả phải sau ngày nhận phòng.', 1;
    IF (SELECT COUNT(*) FROM @DanhSachPhong) <> 1
        THROW 50002, N'Demo Lost Update chỉ minh họa với đúng 1 phòng mỗi lần đặt.', 1;

    DECLARE @MaPhong VARCHAR(10) = (SELECT TOP (1) MaPhong FROM @DanhSachPhong);
    DECLARE @SoDem INT = DATEDIFF(DAY, @NgayNhan, @NgayTra);

    IF NOT EXISTS (SELECT 1 FROM dbo.PHONG WHERE MaPhong = @MaPhong)
        THROW 50003, N'Phòng không tồn tại.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.KHACHHANG WHERE MaKH = @MaKH)
        THROW 50004, N'Khách hàng không tồn tại.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.NHANVIEN WHERE MaNV = @MaNV)
        THROW 50005, N'Nhân viên không tồn tại.', 1;

    ------------------------------------------------------------------
    -- BƯỚC 1 (KHÔNG BẢO VỆ): chỉ ĐỌC xem còn trống hay không.
    ------------------------------------------------------------------
    DECLARE @SoNgayConTrong INT;
    SELECT @SoNgayConTrong = COUNT(*)
    FROM dbo.PHONG_NGAY
    WHERE MaPhong = @MaPhong
      AND Ngay >= @NgayNhan AND Ngay < @NgayTra
      AND MaDatPhong IS NULL;

    IF @SoNgayConTrong <> @SoDem
        THROW 50006, N'Phòng đã có người đặt trong khoảng ngày này.', 1;

    ------------------------------------------------------------------
    -- CỐ TÌNH TẠO KHOẢNG TRỐNG để 2 phiên cùng đọc
    ------------------------------------------------------------------
    WAITFOR DELAY '00:00:05';

    IF @MaDatPhong IS NULL
    BEGIN
        WHILE @MaDatPhong IS NULL OR EXISTS (SELECT 1 FROM dbo.DATPHONG WHERE MaDatPhong = @MaDatPhong)
            SET @MaDatPhong = CONCAT('BK', RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), NEXT VALUE FOR dbo.Seq_MaDatPhong)), 8));
    END;

    DECLARE @GiaCoBan DECIMAL(18,2), @MaLoai VARCHAR(10), @TenLoai NVARCHAR(50);
    SELECT @GiaCoBan = lp.GiaCoBan, @MaLoai = lp.MaLoai, @TenLoai = lp.TenLoai
    FROM dbo.PHONG p JOIN dbo.LOAIPHONG lp ON lp.MaLoai = p.MaLoai
    WHERE p.MaPhong = @MaPhong;

    DECLARE @TongTien DECIMAL(18,2) = CAST(@GiaCoBan * @SoDem AS DECIMAL(18,2));

    ------------------------------------------------------------------
    -- BƯỚC 2 (KHÔNG BẢO VỆ): ghi thẳng, không transaction
    ------------------------------------------------------------------
    INSERT INTO dbo.DATPHONG (MaDatPhong, MaKH, MaNV, TongTien, TrangThai, Version, NgayNhanDuKien, NgayTraDuKien, SoLuongPhongDat)
    VALUES (@MaDatPhong, @MaKH, @MaNV, @TongTien, N'Đã đặt', 1, @NgayNhan, @NgayTra, 1);

    INSERT INTO dbo.DATPHONG_PHONG (MaDatPhong, MaPhong, MaLoai, TenLoai, DonGia, SoDem, ThanhTien)
    VALUES (@MaDatPhong, @MaPhong, @MaLoai, @TenLoai, @GiaCoBan, @SoDem, @TongTien);

    UPDATE dbo.PHONG_NGAY
    SET MaDatPhong = @MaDatPhong
    WHERE MaPhong = @MaPhong
      AND Ngay >= @NgayNhan AND Ngay < @NgayTra;

    SELECT
        @MaDatPhong AS MaDatPhong,
        @MaPhong AS MaPhong,
        @TongTien AS TongTien,
        N'Đã đặt' AS TrangThai,
        N'Đặt phòng thành công (DEMO — KHÔNG BẢO VỆ). Nếu phiên kia đặt cùng phòng, một trong hai booking sẽ mất phòng dù vẫn hiện "Đã đặt".' AS ThongBao;
END
GO
