-- =====================================================================
-- sql/procedures/sp_Demo_NonRepeat_Phantom.sql
-- (Các kịch bản lỗi đồng thời: Non-Repeatable Read & Phantom Read)
-- =====================================================================
USE QL_KhachSan;
GO
CREATE OR ALTER PROC dbo.sp_Demo_XungDot_Reset
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.DATPHONG WHERE MaDatPhong = N'DP_DEMO_NRR';
    INSERT INTO dbo.DATPHONG (MaDatPhong, MaKH, MaNV, TongTien, TrangThai, Version)
    VALUES (N'DP_DEMO_NRR', N'KH01', N'NV01', 500000, N'Đã đặt', 1);

    DELETE FROM dbo.DATPHONG WHERE MaDatPhong = N'DP_DEMO_PHANTOM';

    SELECT N'Đã reset dữ liệu demo Non-repeatable Read / Phantom Read.' AS ThongBao;
END
GO

-- --- CASE: NON-REPEATABLE READ ---
CREATE OR ALTER PROC dbo.sp_Demo_NonRepeatRead_SessionA
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    BEGIN TRAN;
    SELECT 'Lần đọc 1' AS Lan, MaDatPhong, TrangThai FROM dbo.DATPHONG WHERE MaDatPhong = N'DP_DEMO_NRR';
    WAITFOR DELAY '00:00:10';
    SELECT 'Lần đọc 2' AS Lan, MaDatPhong, TrangThai FROM dbo.DATPHONG WHERE MaDatPhong = N'DP_DEMO_NRR';
    COMMIT TRAN;
END
GO
CREATE OR ALTER PROC dbo.sp_Demo_NonRepeatRead_SessionB
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.DATPHONG SET TrangThai = N'Đang ở' WHERE MaDatPhong = N'DP_DEMO_NRR';
    SELECT N'Check-in thành công, đã đổi trạng thái DP_DEMO_NRR.' AS ThongBao;
END
GO
CREATE OR ALTER PROC dbo.sp_Demo_NonRepeatRead_SessionA_Fixed
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    BEGIN TRAN;
    SELECT 'Lần đọc 1 (đã sửa)' AS Lan, MaDatPhong, TrangThai FROM dbo.DATPHONG WITH (HOLDLOCK) WHERE MaDatPhong = N'DP_DEMO_NRR';
    WAITFOR DELAY '00:00:10';
    SELECT 'Lần đọc 2 (đã sửa)' AS Lan, MaDatPhong, TrangThai FROM dbo.DATPHONG WITH (HOLDLOCK) WHERE MaDatPhong = N'DP_DEMO_NRR';
    COMMIT TRAN;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END
GO

-- --- CASE: PHANTOM READ ---
CREATE OR ALTER PROC dbo.sp_Demo_PhantomRead_SessionA
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    BEGIN TRAN;
    SELECT 'Lần quét 1' AS Lan, MaDatPhong, MaKH, TrangThai FROM dbo.DATPHONG WHERE TrangThai = N'Đã đặt' AND MaDatPhong LIKE 'DP_DEMO%';
    WAITFOR DELAY '00:00:10';
    SELECT 'Lần quét 2' AS Lan, MaDatPhong, MaKH, TrangThai FROM dbo.DATPHONG WHERE TrangThai = N'Đã đặt' AND MaDatPhong LIKE 'DP_DEMO%';
    COMMIT TRAN;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END
GO
CREATE OR ALTER PROC dbo.sp_Demo_PhantomRead_SessionB
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.DATPHONG WHERE MaDatPhong = N'DP_DEMO_PHANTOM')
        INSERT INTO dbo.DATPHONG (MaDatPhong, MaKH, MaNV, TongTien, TrangThai, Version)
        VALUES (N'DP_DEMO_PHANTOM', N'KH01', N'NV01', 500000, N'Đã đặt', 1);

    SELECT N'Tạo booking DP_DEMO_PHANTOM thành công!' AS ThongBao;
END
GO
CREATE OR ALTER PROC dbo.sp_Demo_PhantomRead_SessionA_Fixed
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRAN;
    SELECT 'Lần quét 1 (đã sửa)' AS Lan, MaDatPhong, MaKH, TrangThai FROM dbo.DATPHONG WHERE TrangThai = N'Đã đặt' AND MaDatPhong LIKE 'DP_DEMO%';
    WAITFOR DELAY '00:00:10';
    SELECT 'Lần quét 2 (đã sửa)' AS Lan, MaDatPhong, MaKH, TrangThai FROM dbo.DATPHONG WHERE TrangThai = N'Đã đặt' AND MaDatPhong LIKE 'DP_DEMO%';
    COMMIT TRAN;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END
GO
