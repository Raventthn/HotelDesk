USE QL_KhachSan;
GO
-- SSMS: chạy bằng tài khoản có quyền xem trạng thái server.
-- SQL Server 2022+: VIEW SERVER PERFORMANCE STATE; bản trước: VIEW SERVER STATE.
-- Đọc deadlock graph gần đây từ system_health, không thay đổi dữ liệu.
;WITH RingBuffer AS (
 SELECT CAST(t.target_data AS XML) AS Data
 FROM sys.dm_xe_session_targets AS t
 JOIN sys.dm_xe_sessions AS s ON s.address=t.event_session_address
 WHERE s.name=N'system_health' AND t.target_name=N'ring_buffer'
)
SELECT e.value('@timestamp','datetime2') AS UtcTime,
       e.query('(data/value/deadlock)[1]') AS DeadlockGraph
FROM RingBuffer
CROSS APPLY Data.nodes('/RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(e)
ORDER BY UtcTime DESC;
GO
-- Chạy khi hai phiên đang chờ. blocking_session_id khác 0 chưa đủ kết luận deadlock.
SELECT r.session_id,r.blocking_session_id,r.status,r.wait_type,r.wait_resource,
       t.text AS SqlText
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.database_id=DB_ID() AND r.session_id<>@@SPID;
GO
-- Mức RCSI không làm mất khóa của SELECT đã khai báo SERIALIZABLE.
SELECT name,is_read_committed_snapshot_on FROM sys.databases WHERE database_id=DB_ID();
GO
SELECT name,OBJECT_NAME(parent_id) AS TableName,is_disabled
FROM sys.triggers WHERE parent_class=1;
GO
