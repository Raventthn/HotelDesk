USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_TraPhong
    @MaDatPhong VARCHAR(MAX),
    @Version INT,
    @SoTienThanhToan DECIMAL(18, 2) = 0,
    @MaGD VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT <> 0
        THROW 50101, N'Procedure phải được gọi ngoài transaction đang mở.', 1;

    SET XACT_ABORT ON;
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaGD = NULLIF(LTRIM(RTRIM(@MaGD)), '');
    IF @MaDatPhong IS NOT NULL AND (DATALENGTH(@MaDatPhong) > 10 OR @MaDatPhong COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaGD IS NOT NULL AND (DATALENGTH(@MaGD) > 10 OR @MaGD COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;

    IF @MaDatPhong IS NULL OR LTRIM(RTRIM(@MaDatPhong)) = ''
        THROW 50102, N'Mã đặt phòng không được để trống.', 1;

    IF @Version IS NULL OR @Version < 1
        THROW 50103, N'Version phải là số nguyên dương.', 1;

    IF @SoTienThanhToan IS NULL OR @SoTienThanhToan < 0
        THROW 50104, N'Số tiền thanh toán phải lớn hơn hoặc bằng 0.', 1;

    SET @MaGD = NULLIF(LTRIM(RTRIM(@MaGD)), '');

    IF @SoTienThanhToan = 0 AND @MaGD IS NOT NULL
        THROW 50106, N'Không truyền mã giao dịch khi không thu thêm tiền.', 1;

    DECLARE @TrangThai NVARCHAR(50);
    DECLARE @VersionHienTai INT;
    DECLARE @TongTien DECIMAL(18, 2);
    DECLARE @DaThuRong DECIMAL(28, 2);
    DECLARE @ConPhaiTra DECIMAL(28, 2);
    DECLARE @CoGiaoDichSai INT;
    DECLARE @NgayCuoiSomNhat DATE;
    DECLARE @NgayCuoiMuonNhat DATE;
    DECLARE @NgayNhanMuonNhat DATE;
    DECLARE @NgayTraDuKien DATE;
    DECLARE @NgayTraThucTe DATE;
    DECLARE @SoDemPhongGiaiPhong INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

   
        SELECT
            @TrangThai = dp.TrangThai,
            @VersionHienTai = dp.Version,
            @TongTien = dp.TongTien
        FROM dbo.DATPHONG AS dp WITH (UPDLOCK, HOLDLOCK)
        WHERE dp.MaDatPhong = @MaDatPhong;

        IF @VersionHienTai IS NULL
            THROW 50107, N'Booking không tồn tại hoặc thiếu Version.', 1;

        IF @VersionHienTai <> @Version
            THROW 50109, N'Booking đã thay đổi. Vui lòng tải lại dữ liệu.', 1;

        IF @TrangThai IS NULL OR @TrangThai <> N'Đang ở'
            THROW 50108, N'Chỉ được trả phòng cho booking có trạng thái Đang ở.', 1;

        IF @TongTien IS NULL OR @TongTien < 0
            THROW 50110, N'Booking chưa có tổng tiền hợp lệ.', 1;

        SELECT
            @NgayCuoiSomNhat = MIN(lich.NgayCuoi),
            @NgayCuoiMuonNhat = MAX(lich.NgayCuoi),
            @NgayNhanMuonNhat = MAX(lich.NgayNhan)
        FROM (
            SELECT
                pn.MaPhong,
                MIN(pn.Ngay) AS NgayNhan,
                MAX(pn.Ngay) AS NgayCuoi
            FROM dbo.PHONG_NGAY AS pn WITH (UPDLOCK, HOLDLOCK)
            WHERE pn.MaDatPhong = @MaDatPhong
            GROUP BY pn.MaPhong
        ) AS lich;

        IF @NgayCuoiSomNhat IS NULL
            THROW 50111, N'Booking không có lịch phòng để xác định ngày trả.', 1;
        IF NOT EXISTS(SELECT 1 FROM dbo.vw_KiemTraLichBooking WHERE MaDatPhong=@MaDatPhong AND LichHopLe=1)
            THROW 50120, N'Lịch phòng không khớp booking. Cần kiểm tra trước khi trả phòng.', 1;

        IF @NgayCuoiSomNhat <> @NgayCuoiMuonNhat
            THROW 50112, N'Các phòng trong booking phải có cùng ngày trả.', 1;

        SET @NgayTraDuKien = DATEADD(DAY, 1, @NgayCuoiMuonNhat);
        SET @NgayTraThucTe = CONVERT(DATE, GETDATE());

        IF @NgayTraThucTe < @NgayNhanMuonNhat
            THROW 50119, N'Ngày trả không được trước ngày bắt đầu lưu trú của các phòng.', 1;

        -- Ở tiếp phải tạo booking mới; đóng booking cũ theo tổng tiền đã chốt.
        -- Cho phép đóng muộn, không kéo dài lịch hoặc tự thu thêm tiền.


        UPDATE dbo.PHONG_NGAY
        SET MaDatPhong = NULL
        WHERE MaDatPhong = @MaDatPhong
          AND Ngay >= @NgayTraThucTe;

        SET @SoDemPhongGiaiPhong = @@ROWCOUNT;


        SELECT
            @DaThuRong = COALESCE(SUM(
                CASE
                    WHEN tt.LoaiGiaoDich IN (N'Đặt cọc', N'Thanh toán')
                        THEN tt.SoTien
                    WHEN tt.LoaiGiaoDich = N'Hoàn tiền'
                        THEN -tt.SoTien
                    ELSE 0
                END
            ), 0),
            @CoGiaoDichSai = COALESCE(MAX(
                CASE
                    WHEN tt.LoaiGiaoDich IS NULL
                      OR tt.LoaiGiaoDich NOT IN
                         (N'Đặt cọc', N'Thanh toán', N'Hoàn tiền')
                      OR tt.SoTien IS NULL OR tt.SoTien <= 0
                        THEN 1
                    ELSE 0
                END
            ), 0)
        FROM dbo.THANHTOAN AS tt WITH (UPDLOCK, HOLDLOCK)
        WHERE tt.MaDatPhong = @MaDatPhong;

        IF @CoGiaoDichSai = 1
            THROW 50114, N'Có giao dịch sai số tiền hoặc loại giao dịch chưa được hỗ trợ.', 1;

        IF @DaThuRong < 0
            THROW 50115, N'Tổng tiền hoàn đang vượt tiền đã thu. Cần kiểm tra giao dịch.', 1;

        SET @ConPhaiTra = @TongTien - @DaThuRong;

        IF @ConPhaiTra < 0
            THROW 50116, N'Khách đã nộp dư. Cần xử lý hoàn tiền trước khi trả phòng.', 1;

        IF @SoTienThanhToan <> @ConPhaiTra
            THROW 50117, N'Khoản thu xác nhận phải bằng số tiền còn phải trả. Hãy tải lại số dư.', 1;

        IF @SoTienThanhToan > 0
        BEGIN
            DECLARE @MaGDCuSo VARCHAR(30) = CONCAT(@MaDatPhong, '_TT');
            DECLARE @SoThuTuGiaoDich INT = 1;
            SET @MaGD = @MaGDCuSo;
            WHILE EXISTS (SELECT 1 FROM dbo.THANHTOAN WHERE MaGD = @MaGD)
            BEGIN
                SET @SoThuTuGiaoDich += 1;
                SET @MaGD = CONCAT(@MaGDCuSo, RIGHT(CONCAT('0', @SoThuTuGiaoDich), 2));
            END;

            INSERT INTO dbo.THANHTOAN
                (MaGD, MaDatPhong, SoTien, LoaiGiaoDich, NgayGD)
            VALUES
                (@MaGD, @MaDatPhong, @SoTienThanhToan, N'Thanh toán', GETDATE());
        END;

        UPDATE dbo.DATPHONG
        SET TrangThai = N'Đã trả',
            NgayTraThucTe = @NgayTraThucTe,
            Version = Version + 1
        WHERE MaDatPhong = @MaDatPhong
          AND TrangThai = N'Đang ở'
          AND Version = @Version;

        IF @@ROWCOUNT <> 1
            THROW 50118, N'Không thể hoàn tất trả phòng. Vui lòng tải lại booking.', 1;

        SELECT @VersionHienTai = dp.Version
        FROM dbo.DATPHONG AS dp
        WHERE dp.MaDatPhong = @MaDatPhong;

        COMMIT TRANSACTION;

        SELECT
            @MaDatPhong AS MaDatPhong,
            N'Đã trả' AS TrangThai,
            @TongTien AS TongTien,
            @DaThuRong AS DaThanhToanRongTruocDo,
            @SoTienThanhToan AS ThuThem,
            @DaThuRong + @SoTienThanhToan AS DaThanhToanRong,
            CAST(0 AS DECIMAL(18, 2)) AS ConPhaiTra,
            @MaGD AS MaGiaoDichMoi,
            @VersionHienTai AS Version,
            @NgayTraDuKien AS NgayTraDuKienTruocKhiTra,
            @NgayTraThucTe AS NgayTraThucTe,
            @SoDemPhongGiaiPhong AS SoDemPhongGiaiPhong,
            N'Trả phòng thành công.' AS ThongBao;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
