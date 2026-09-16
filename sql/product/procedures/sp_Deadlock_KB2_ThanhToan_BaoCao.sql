USE QL_KhachSan;
GO
-- =========================================================
-- DEMO DEADLOCK KB2: Thanh toán (Ghi) vs Báo cáo (Đọc)
-- =========================================================

-- 1. SP Thanh Toán (Lễ tân thực hiện)
CREATE OR ALTER PROCEDURE SP_ThanhToan
    @MaGD VARCHAR(30),
    @MaDatPhong VARCHAR(10),
    @SoTien DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Bước 1: Khóa & Cập nhật bảng DATPHONG
        UPDATE DATPHONG 
        SET TrangThai = N'Đã thanh toán' 
        WHERE MaDatPhong = @MaDatPhong;

        -- Tạo độ trễ 2 giây để giả lập tiến trình đang xử lý
        WAITFOR DELAY '00:00:02'; 

        -- Bước 2: Thêm bản ghi vào bảng THANHTOAN
        INSERT INTO THANHTOAN (MaGD, MaDatPhong, SoTien, LoaiGiaoDich, NgayGD)
        VALUES (@MaGD, @MaDatPhong, @SoTien, N'Thanh toán', GETDATE());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 2. SP Báo Cáo - Bản LỖI (Gây Deadlock KB2 với Thanh Toán)
CREATE OR ALTER PROCEDURE SP_BaoCao_Loi
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Khóa ngược thứ tự: Giữ khóa trên THANHTOAN trước
        SELECT SUM(SoTien) AS TongDoanhThu 
        FROM THANHTOAN WITH (TABLOCKX);

        WAITFOR DELAY '00:00:02';

        -- Sau đó mới đòi đọc DATPHONG -> Gây Deadlock với SP_ThanhToan
        SELECT TrangThai, COUNT(*) AS SoLuong 
        FROM DATPHONG WITH (TABLOCKX)
        GROUP BY TrangThai;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3. SP Báo Cáo - Bản FIX (Dùng READ UNCOMMITTED để tránh Deadlock)
CREATE OR ALTER PROCEDURE SP_BaoCao
AS
BEGIN
    SET NOCOUNT ON;
    -- Cho phép đọc dữ liệu báo cáo mà không cần chờ khóa ghi
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; 

    SELECT SUM(SoTien) AS TongDoanhThu FROM THANHTOAN;
    SELECT TrangThai, COUNT(*) AS SoLuong FROM DATPHONG GROUP BY TrangThai;
END;
GO