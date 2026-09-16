USE QL_KhachSan;
GO

-- Phí giữ lại từ tiền đã thu; phần còn lại được hoàn, không tạo khoản thu giả.
CREATE OR ALTER PROCEDURE dbo.sp_NoShow_NhaPhong
    @MaDatPhong VARCHAR(MAX),
    @Version INT,
    @PhiPhat DECIMAL(18,2),
    @SoTienHoanTra DECIMAL(18,2) = 0,
    @MaGDHoanTien VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @@TRANCOUNT <> 0
        THROW 51500, N'Procedure phải được gọi ngoài transaction đang mở.', 1;
    SET XACT_ABORT ON;
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaGDHoanTien = NULLIF(LTRIM(RTRIM(@MaGDHoanTien)), '');
    IF @MaDatPhong IS NOT NULL AND (DATALENGTH(@MaDatPhong) > 10 OR @MaDatPhong COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaGDHoanTien IS NOT NULL AND (DATALENGTH(@MaGDHoanTien) > 10 OR @MaGDHoanTien COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaDatPhong IS NULL OR LTRIM(RTRIM(@MaDatPhong)) = '' OR @Version IS NULL OR @Version < 1
        THROW 51501, N'Cần mã booking và Version hợp lệ.', 1;
    IF @PhiPhat IS NULL OR @PhiPhat < 0 OR @SoTienHoanTra IS NULL OR @SoTienHoanTra < 0
        THROW 51502, N'Phí no-show và tiền hoàn không được âm.', 1;
    SET @MaGDHoanTien = NULLIF(LTRIM(RTRIM(@MaGDHoanTien)), '');
    IF @SoTienHoanTra = 0 AND @MaGDHoanTien IS NOT NULL
        THROW 51503, N'Không truyền mã giao dịch khi không có tiền hoàn.', 1;

    DECLARE @TrangThai NVARCHAR(50), @VersionHienTai INT, @NgayNhan DATE, @TongTien DECIMAL(18,2);
    DECLARE @NgayNhanLich DATE, @NgayNhanMuonNhat DATE, @NgayTra DATE, @SoPhong INT;
    DECLARE @NgayTraLuu DATE, @SoPhongLuu INT, @NgayCuoiSomNhat DATE, @NgayCuoiMuonNhat DATE, @ThieuNgay INT;
    DECLARE @DaThuRong DECIMAL(28,2), @GiaoDichSai INT, @ThoiDiem DATETIME2(0) = SYSDATETIME();
    BEGIN TRY
        BEGIN TRAN;
        SELECT @TrangThai = TrangThai, @VersionHienTai = Version, @NgayNhan = NgayNhanDuKien, @TongTien = TongTien,
               @NgayTraLuu = NgayTraDuKien, @SoPhongLuu = SoLuongPhongDat
        FROM dbo.DATPHONG WITH (UPDLOCK, HOLDLOCK) WHERE MaDatPhong = @MaDatPhong;
        IF @VersionHienTai IS NULL THROW 51504, N'Booking không tồn tại.', 1;
        IF @VersionHienTai <> @Version THROW 51505, N'Booking đã thay đổi. Tải lại dữ liệu và chọn lại booking.', 1;
        IF @TrangThai <> N'Đã đặt' THROW 51506, N'Chỉ xử lý no-show cho booking chưa nhận phòng.', 1;

        SELECT @NgayNhanLich = MIN(NgayNhan), @NgayNhanMuonNhat = MAX(NgayNhan),
               @NgayTra = DATEADD(DAY, 1, MAX(NgayCuoi)), @SoPhong = COUNT(*),
               @NgayCuoiSomNhat = MIN(NgayCuoi), @NgayCuoiMuonNhat = MAX(NgayCuoi),
               @ThieuNgay = MAX(CASE WHEN SoNgay <> DATEDIFF(DAY, NgayNhan, NgayCuoi) + 1 THEN 1 ELSE 0 END)
        FROM (
            SELECT MaPhong, MIN(Ngay) AS NgayNhan, MAX(Ngay) AS NgayCuoi, COUNT(*) AS SoNgay
            FROM dbo.PHONG_NGAY WITH (UPDLOCK, HOLDLOCK)
            WHERE MaDatPhong = @MaDatPhong GROUP BY MaPhong
        ) lich;
        IF @NgayNhanLich IS NULL OR @NgayNhanLich <> @NgayNhanMuonNhat
            OR (@NgayNhan IS NOT NULL AND @NgayNhan <> @NgayNhanLich)
            OR @NgayCuoiSomNhat <> @NgayCuoiMuonNhat OR @ThieuNgay = 1
            OR (@NgayTraLuu IS NOT NULL AND @NgayTraLuu <> @NgayTra)
            OR (@SoPhongLuu IS NOT NULL AND @SoPhongLuu <> @SoPhong)
            THROW 51507, N'Lịch phòng thiếu hoặc không nhất quán; cần kiểm tra booking.', 1;
        SET @NgayNhan = COALESCE(@NgayNhan, @NgayNhanLich);
        IF NOT EXISTS(SELECT 1 FROM dbo.vw_KiemTraLichBooking WHERE MaDatPhong=@MaDatPhong AND LichHopLe=1)
            THROW 51507, N'Lịch phòng không khớp booking. Cần kiểm tra dữ liệu.', 1;
        IF CONVERT(DATE, @ThoiDiem) <= @NgayNhan
            THROW 51508, N'Chỉ xử lý no-show từ ngày sau ngày nhận dự kiến.', 1;

        SELECT @DaThuRong = COALESCE(SUM(CASE
                   WHEN LoaiGiaoDich IN (N'Đặt cọc', N'Thanh toán') THEN SoTien
                   WHEN LoaiGiaoDich = N'Hoàn tiền' THEN -SoTien ELSE 0 END), 0),
               @GiaoDichSai = COALESCE(MAX(CASE WHEN SoTien <= 0 OR SoTien IS NULL
                   OR LoaiGiaoDich IS NULL OR LoaiGiaoDich NOT IN (N'Đặt cọc', N'Thanh toán', N'Hoàn tiền')
                   THEN 1 ELSE 0 END), 0)
        FROM dbo.THANHTOAN WITH (UPDLOCK, HOLDLOCK) WHERE MaDatPhong = @MaDatPhong;
        IF @GiaoDichSai = 1 OR @DaThuRong < 0 OR @TongTien IS NULL OR @TongTien < 0 OR @DaThuRong > @TongTien
            THROW 51509, N'Dữ liệu thanh toán bất thường; cần đối soát trước khi xử lý no-show.', 1;
        IF @PhiPhat > @DaThuRong
            THROW 51510, N'Phí no-show không được vượt tiền đã thu ròng.', 1;
        IF @SoTienHoanTra <> @DaThuRong - @PhiPhat
            THROW 51511, N'Tiền hoàn phải bằng tiền đã thu ròng trừ phí no-show. Tải lại số dư.', 1;

        IF @SoTienHoanTra > 0
        BEGIN
            DECLARE @MaGDCuSo VARCHAR(30) = CONCAT(@MaDatPhong, '_NS');
            DECLARE @SoThuTuGiaoDich INT = 1;
            SET @MaGDHoanTien = @MaGDCuSo;
            WHILE EXISTS (SELECT 1 FROM dbo.THANHTOAN WHERE MaGD = @MaGDHoanTien)
            BEGIN
                SET @SoThuTuGiaoDich += 1;
                SET @MaGDHoanTien = CONCAT(@MaGDCuSo, RIGHT(CONCAT('0', @SoThuTuGiaoDich), 2));
            END;

            INSERT dbo.THANHTOAN (MaGD, MaDatPhong, SoTien, LoaiGiaoDich, NgayGD)
            VALUES (@MaGDHoanTien, @MaDatPhong, @SoTienHoanTra, N'Hoàn tiền', @ThoiDiem);
        END;
        UPDATE dbo.PHONG_NGAY SET MaDatPhong = NULL WHERE MaDatPhong = @MaDatPhong;
        UPDATE dbo.DATPHONG
        SET TrangThai = N'No-show', Version = Version + 1, PhiNoShow = @PhiPhat, NgayXuLyNoShow = @ThoiDiem,
            NgayNhanDuKien = @NgayNhan, NgayTraDuKien = COALESCE(NgayTraDuKien, @NgayTra),
            SoLuongPhongDat = COALESCE(SoLuongPhongDat, @SoPhong)
        WHERE MaDatPhong = @MaDatPhong AND Version = @Version;
        IF @@ROWCOUNT <> 1 THROW 51505, N'Booking đã thay đổi. Tải lại dữ liệu và chọn lại booking.', 1;
        COMMIT;
        SELECT @MaDatPhong AS MaDatPhong, N'No-show' AS TrangThai, @Version + 1 AS Version,
               @PhiPhat AS PhiNoShow, @SoTienHoanTra AS HoanTien, @PhiPhat AS DaThanhToanRong,
             CAST(0 AS DECIMAL(18,2)) AS ConPhaiTra, @MaGDHoanTien AS MaGiaoDichMoi,
             @ThoiDiem AS NgayXuLyNoShow,
               N'Đã xử lý no-show và giải phóng phòng.' AS ThongBao;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
