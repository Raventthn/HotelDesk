USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DatPhong
    @MaDatPhong   VARCHAR(MAX),
    @MaKH         VARCHAR(MAX),
    @DanhSachPhong dbo.DanhSachPhongDat READONLY,
    @NgayNhan     DATE,
    @NgayTra      DATE,
    @MaNV         VARCHAR(MAX) = 'WEB'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaKH = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @MaNV = NULLIF(LTRIM(RTRIM(@MaNV)), '');
    IF @MaDatPhong IS NOT NULL AND (DATALENGTH(@MaDatPhong) > 10 OR @MaDatPhong COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaKH IS NOT NULL AND (DATALENGTH(@MaKH) > 10 OR @MaKH COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaNV IS NOT NULL AND (DATALENGTH(@MaNV) > 10 OR @MaNV COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;

    ------------------------------------------------------------
    -- 1. Không cho gọi SP bên trong transaction khác
    ------------------------------------------------------------
    IF @@TRANCOUNT <> 0
        THROW 51400,
              N'Procedure phải được gọi ngoài transaction đang mở.',
              1;

    ------------------------------------------------------------
    -- 2. Chuẩn hóa dữ liệu
    ------------------------------------------------------------
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaKH       = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @MaNV       = NULLIF(LTRIM(RTRIM(@MaNV)), '');

    ------------------------------------------------------------
    -- 3. Kiểm tra dữ liệu bắt buộc
    ------------------------------------------------------------
    IF @MaKH IS NULL
       OR @MaNV IS NULL
    BEGIN
        THROW 51401,
              N'Mã booking, khách hàng và nhân viên không được để trống.',
              1;
    END;

    ------------------------------------------------------------
    -- 4. Kiểm tra ngày
    ------------------------------------------------------------
    IF @NgayNhan IS NULL
       OR @NgayTra IS NULL
    BEGIN
        THROW 51402,
              N'Ngày nhận và ngày trả không được để trống.',
              1;
    END;

    IF @NgayNhan < CONVERT(DATE, GETDATE())
    BEGIN
        THROW 51403,
              N'Ngày nhận phòng không được nằm trong quá khứ.',
              1;
    END;

    IF @NgayTra <= @NgayNhan
    BEGIN
        THROW 51404,
              N'Ngày trả phải sau ngày nhận phòng.',
              1;
    END;

    IF DATEDIFF(DAY, @NgayNhan, @NgayTra) > 366
    BEGIN
        THROW 51405,
              N'Mỗi booking chỉ được đặt tối đa 366 đêm.',
              1;
    END;

    ------------------------------------------------------------
    -- 5. Kiểm tra danh sách phòng
    ------------------------------------------------------------
    IF NOT EXISTS
    (
        SELECT 1
        FROM @DanhSachPhong
    )
    BEGIN
        THROW 51406,
              N'Booking phải có ít nhất một phòng.',
              1;
    END;

    -- Không cho MaPhong NULL hoặc rỗng
    IF EXISTS
    (
        SELECT 1
        FROM @DanhSachPhong
        WHERE MaPhong IS NULL
           OR LTRIM(RTRIM(MaPhong)) = ''
    )
    BEGIN
        THROW 51407,
              N'Mã phòng không được để trống.',
              1;
    END;

    -- Không cho cùng phòng xuất hiện nhiều lần
    IF EXISTS
    (
        SELECT MaPhong
        FROM @DanhSachPhong
        GROUP BY MaPhong
        HAVING COUNT(*) > 1
    )
    BEGIN
        THROW 51408,
              N'Một phòng không được xuất hiện nhiều lần trong cùng booking.',
              1;
    END;

    ------------------------------------------------------------
    -- 6. Các biến xử lý
    ------------------------------------------------------------
    DECLARE @SoDem INT =
        DATEDIFF(DAY, @NgayNhan, @NgayTra);

    DECLARE @SoPhong INT =
    (
        SELECT COUNT(*)
        FROM @DanhSachPhong
    );

    DECLARE @TongTien DECIMAL(18,2);

    DECLARE @SoPhongHopLe INT;

    DECLARE @GiaNhoNhat DECIMAL(18,2);

    DECLARE @SoDongCanDat INT =
        @SoPhong * @SoDem;

    DECLARE @SoDongDaDat INT;

    ------------------------------------------------------------
    -- 7. Transaction đặt phòng
    ------------------------------------------------------------
    BEGIN TRY

        BEGIN TRAN;

        IF @MaDatPhong IS NULL
        BEGIN
            WHILE @MaDatPhong IS NULL
               OR EXISTS (SELECT 1 FROM dbo.DATPHONG WITH (UPDLOCK, HOLDLOCK) WHERE MaDatPhong = @MaDatPhong)
            BEGIN
                SET @MaDatPhong = CONCAT(
                    'BK',
                    RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), NEXT VALUE FOR dbo.Seq_MaDatPhong)), 8)
                );
            END;
        END;

        --------------------------------------------------------
        -- 7.1 Kiểm tra booking chưa tồn tại
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.DATPHONG WITH (UPDLOCK, HOLDLOCK)
            WHERE MaDatPhong = @MaDatPhong
        )
        BEGIN
            THROW 51409,
                  N'Mã booking đã tồn tại.',
                  1;
        END;

        --------------------------------------------------------
        -- 7.2 Kiểm tra khách hàng
        --------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.KHACHHANG WITH (HOLDLOCK)
            WHERE MaKH = @MaKH
        )
        BEGIN
            THROW 51410,
                  N'Khách hàng không tồn tại.',
                  1;
        END;

        --------------------------------------------------------
        -- 7.3 Kiểm tra nhân viên
        --
        -- WEB cũng phải tồn tại trong NHANVIEN để thỏa khóa ngoại.
        --------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.NHANVIEN WITH (HOLDLOCK)
            WHERE MaNV = @MaNV
        )
        BEGIN
            THROW 51411,
                  N'Nhân viên không tồn tại.',
                  1;
        END;

        --------------------------------------------------------
        -- 7.4 Kiểm tra phòng tồn tại + tính tổng tiền
        --------------------------------------------------------
        SELECT
            @SoPhongHopLe = COUNT(*),

            @GiaNhoNhat = MIN(lp.GiaCoBan),

            @TongTien =
                CAST(
                    SUM(
                        CAST(lp.GiaCoBan AS DECIMAL(28,2))
                    ) * @SoDem
                    AS DECIMAL(18,2)
                )

        FROM @DanhSachPhong ds

        INNER JOIN dbo.PHONG p WITH (HOLDLOCK)
            ON p.MaPhong = ds.MaPhong

        INNER JOIN dbo.LOAIPHONG lp WITH (HOLDLOCK)
            ON lp.MaLoai = p.MaLoai;

        --------------------------------------------------------
        -- Có phòng không tồn tại
        --------------------------------------------------------
        IF @SoPhongHopLe <> @SoPhong
        BEGIN
            THROW 51412,
                  N'Có phòng không tồn tại trong hệ thống.',
                  1;
        END;

        --------------------------------------------------------
        -- Giá phòng không hợp lệ
        --------------------------------------------------------
        IF @TongTien IS NULL
           OR @GiaNhoNhat IS NULL
           OR @GiaNhoNhat < 0
        BEGIN
            THROW 51413,
                  N'Giá phòng không hợp lệ.',
                  1;
        END;

        --------------------------------------------------------
        -- 7.4.1 Khóa các phòng theo thứ tự cố định.
        -- Mọi giao tác đặt phòng lấy khóa PHONG tăng dần theo MaPhong,
        -- nên hai booking chồng lấn sẽ chờ tuần tự thay vì tạo vòng chờ.
        --------------------------------------------------------
        DECLARE @MaPhongKhoa VARCHAR(10), @MaPhongDaKhoa VARCHAR(10);
        DECLARE PhongDatKhoa CURSOR LOCAL FAST_FORWARD FOR
            SELECT MaPhong
            FROM @DanhSachPhong
            ORDER BY MaPhong;

        OPEN PhongDatKhoa;
        FETCH NEXT FROM PhongDatKhoa INTO @MaPhongKhoa;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @MaPhongDaKhoa = MaPhong
            FROM dbo.PHONG WITH (UPDLOCK, HOLDLOCK)
            WHERE MaPhong = @MaPhongKhoa;

            FETCH NEXT FROM PhongDatKhoa INTO @MaPhongKhoa;
        END;
        CLOSE PhongDatKhoa;
        DEALLOCATE PhongDatKhoa;

        --------------------------------------------------------
        -- 7.5 Tạo booking
        --------------------------------------------------------
        INSERT INTO dbo.DATPHONG
        (
            MaDatPhong,
            MaKH,
            MaNV,
            TongTien,
            TrangThai,
            Version,
            NgayNhanDuKien,
            NgayTraDuKien,
            SoLuongPhongDat
        )
        VALUES
        (
            @MaDatPhong,
            @MaKH,
            @MaNV,
            @TongTien,
            N'Đã đặt',
            1,
            @NgayNhan,
            @NgayTra,
            @SoPhong
        );

        --------------------------------------------------------
        -- 7.6 Chiếm các ngày phòng
        --
        -- Ngày nhận: có chiếm
        -- Ngày trả: KHÔNG chiếm
        --
        -- Ví dụ:
        -- 10 -> 12
        --
        -- Chiếm:
        -- 10
        -- 11
        --
        -- Không chiếm ngày 12.
        --------------------------------------------------------
        INSERT dbo.DATPHONG_PHONG(MaDatPhong, MaPhong, MaLoai, TenLoai, DonGia, SoDem, ThanhTien)
        SELECT @MaDatPhong, p.MaPhong, lp.MaLoai, lp.TenLoai, lp.GiaCoBan, @SoDem,
               CAST(lp.GiaCoBan * @SoDem AS DECIMAL(18,2))
        FROM @DanhSachPhong ds JOIN dbo.PHONG p ON p.MaPhong=ds.MaPhong
        JOIN dbo.LOAIPHONG lp ON lp.MaLoai=p.MaLoai;

        UPDATE pn WITH (ROWLOCK)
        SET pn.MaDatPhong = @MaDatPhong

        FROM dbo.PHONG_NGAY pn

        INNER JOIN @DanhSachPhong ds
            ON ds.MaPhong = pn.MaPhong

        WHERE pn.Ngay >= @NgayNhan
          AND pn.Ngay < @NgayTra
          AND pn.MaDatPhong IS NULL;

        SET @SoDongDaDat = @@ROWCOUNT;

        --------------------------------------------------------
        -- 7.7 Phải chiếm đủ:
        --
        -- số phòng × số đêm
        --
        -- Ví dụ:
        -- 3 phòng
        -- 2 đêm
        --
        -- cần UPDATE đúng 6 dòng.
        --------------------------------------------------------
        IF @SoDongDaDat <> @SoDongCanDat
        BEGIN
            THROW 51414,
                  N'Một hoặc nhiều phòng đã được đặt hoặc chưa có đủ lịch phòng. Vui lòng tải lại kết quả tra cứu.',
                  1;
        END;

        --------------------------------------------------------
        -- 7.8 Thành công
        --------------------------------------------------------
        COMMIT;

        --------------------------------------------------------
        -- 8. Trả kết quả
        --------------------------------------------------------
        SELECT
            @MaDatPhong AS MaDatPhong,
            @MaKH AS MaKH,
            @NgayNhan AS NgayNhanDuKien,
            @NgayTra AS NgayTraDuKien,
            @SoPhong AS SoLuongPhong,
            @SoDem AS SoDem,
            @TongTien AS TongTien,
            N'Đã đặt' AS TrangThai,
            1 AS Version,
            N'Đặt phòng thành công.' AS ThongBao;

    END TRY

    BEGIN CATCH

        IF XACT_STATE() <> 0
            ROLLBACK;

        THROW;

    END CATCH;
END;
GO
