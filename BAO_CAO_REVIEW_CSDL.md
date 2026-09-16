# Báo cáo review cơ sở dữ liệu – HotelDesk ASP.NET Blazor

## 1. Phạm vi và nguồn phân tích

Báo cáo được lập từ các script trong thư mục `sql/` và mã ứng dụng trong `HotelDesk/`. Các nguồn chính gồm:

- `sql/00_create_new_database.sql`: cấu trúc database gốc `QL_KhachSan`.
- `sql/schema/01_booking_schema.sql`: nâng cấp schema, bổ sung lịch sử booking và index.
- `sql/01_install_views_and_procedures.sql`: thứ tự cài đặt view/procedure.
- `sql/product/view/`: các view dùng cho chức năng sản phẩm.
- `sql/product/procedures/`: các stored procedure nghiệp vụ chính.
- `sql/procedures/`: các procedure/demo phục vụ minh họa lỗi đồng thời.
- `HotelDesk/Services/HotelService.cs`, `HotelDesk/Models/Contracts.cs`: cách ứng dụng gọi database.

## 2. Kiến trúc dữ liệu tổng quát

Hệ thống quản lý khách sạn xoay quanh một booking (`DATPHONG`). Booking liên kết tới khách hàng, nhân viên, các ngày/phòng được giữ chỗ và các giao dịch tiền:

```text
LOAIPHONG 1 ── n PHONG 1 ── n PHONG_NGAY n ── 1 DATPHONG n ── 1 KHACHHANG
                                      │                    └── n THANHTOAN
                                      └── n DATPHONG_PHONG (snapshot phòng/giá)

NHANVIEN 1 ── n DATPHONG
KHACHHANG 1 ── n DANHSACHCHO ── n LOAIPHONG
```

`PHONG_NGAY` là lịch dạng lưới: mỗi cặp `(MaPhong, Ngay)` có một dòng; `MaDatPhong = NULL` nghĩa là ngày còn trống, có giá trị nghĩa là ngày đã bị booking chiếm. Các procedure booking cập nhật lưới này trong transaction để tránh bán trùng phòng.

## 3. Danh mục bảng

### 3.1. Bảng nghiệp vụ chính

| Bảng | Vai trò và dữ liệu chính | Được dùng trong trường hợp nào | Tại sao cần dùng |
|---|---|---|---|
| `LOAIPHONG` | Danh mục loại phòng: `MaLoai`, `TenLoai`, `GiaCoBan`. | Khai báo Standard/VIP, tra cứu giá, báo cáo doanh thu theo loại. | Tách thông tin chung khỏi từng phòng vật lý, tránh lặp giá và tên loại. |
| `PHONG` | Phòng vật lý: `MaPhong`, `SoPhong`, `MaLoai`. | Quản lý phòng cụ thể và xác định phòng thuộc loại nào. | Cho phép một loại phòng có nhiều phòng; là khóa gốc để lập lịch và đặt phòng. |
| `NHANVIEN` | Nhân viên tạo/xử lý booking: `MaNV`, `HoTen`, `VaiTro`. | Chọn nhân viên khi tạo booking; truy xuất người tạo booking. | Bảo đảm booking tham chiếu tới actor hợp lệ; tài khoản `WEB` dùng cho tự động. |
| `KHACHHANG` | Hồ sơ khách: tên, điện thoại, email, CCCD. | Chọn khách cũ hoặc tạo khách mới khi đặt phòng. | Tách dữ liệu khách khỏi booking để một khách có thể có nhiều booking. |
| `DATPHONG` | Header booking: khách, nhân viên, tổng tiền, trạng thái, version, ngày dự kiến, số phòng, phí no-show, ngày trả thực tế. | Toàn bộ vòng đời: đặt, cọc, nhận, trả, hủy, no-show, đối soát. | Thực thể giao dịch trung tâm, giữ trạng thái hiện tại và dữ liệu tổng hợp nhanh. |
| `PHONG_NGAY` | Lịch sử dụng phòng theo ngày và booking đang chiếm; khóa chính `(MaPhong, Ngay)`. | Tìm phòng trống, giữ chỗ, nhận/trả/hủy/no-show, giám sát lịch. | Khóa tự nhiên theo phòng-ngày giúp kiểm tra đủ số đêm và ngăn chiếm trùng. |
| `THANHTOAN` | Sổ giao dịch tiền: đặt cọc, thanh toán, hoàn tiền; liên kết `MaDatPhong`. | Ghi nhận mọi lần thu/hoàn và tính số đã thu ròng. | Lưu từng giao dịch thay vì ghi đè số dư, tạo audit trail và hỗ trợ đối soát. |
| `DANHSACHCHO` | Waitlist: khách, loại phòng, ngày mong muốn, trạng thái. | Dự kiến dùng khi hết phòng và cần xếp khách chờ. | Giữ nhu cầu khách thay vì mất thông tin; hiện chưa thấy UI/service production sử dụng. |
| `DATPHONG_PHONG` | Chi tiết bất biến: phòng, loại phòng, tên loại, đơn giá, số đêm, thành tiền. | Booking mới, báo cáo doanh thu, truy nguyên giá/phòng tại thời điểm đặt. | Giá/tên loại trong danh mục có thể đổi; snapshot giữ nguyên lịch sử tài chính. |

### 3.2. Bảng phục vụ demo

`DEMO_BookingRace_Run`, `DEMO_BookingRace_Request`, `DEMO_BookingRace_Night` trong `sql/schema/03_booking_race_demo.sql` chỉ là fixture cô lập để mô phỏng hai actor cùng đặt phòng. Chúng không thuộc luồng nghiệp vụ thật và không được `HotelService` dùng để lưu booking.

`00_create_demo_database.sql` tạo database `QL_KhachSan_Demo`, trong khi phần cài đặt product dùng `USE QL_KhachSan`. Khi chạy demo cần xác nhận đúng database đích.

## 4. Kiểu dữ liệu, khóa và tính toàn vẹn

- Toàn bộ bảng nghiệp vụ có khóa chính; `PHONG_NGAY` dùng khóa ghép đúng với bài toán phòng-ngày.
- Khóa ngoại bảo vệ liên kết phòng–loại phòng, booking–khách/nhân viên, lịch–phòng/booking, thanh toán–booking.
- `DATPHONG_PHONG` có check đơn giá/thành tiền không âm và số đêm từ 1 đến 366.
- `DanhSachPhongDat` là table-valued type có khóa `MaPhong`, dùng truyền nhiều phòng vào `sp_DatPhong`.
- `Seq_MaDatPhong` và `Seq_MaKhachHang` sinh mã tự động, giảm nguy cơ trùng khi nhiều request đồng thời.
- `Version` trong `DATPHONG` là optimistic concurrency token; procedure chỉ cập nhật khi version từ UI vẫn khớp.
- `IX_PHONG_NGAY_Booking` hỗ trợ truy vấn theo booking/phòng/ngày; `IX_THANHTOAN_Booking` hỗ trợ tổng hợp giao dịch theo booking.

## 5. Danh mục view

| View | Nội dung/tác dụng | Trường hợp sử dụng và lý do |
|---|---|---|
| `vw_TraCuuPhong` | Ghép phòng, loại phòng và từng dòng lịch; trả phòng, loại, giá, ngày, booking đang chiếm. | `SearchRoomsAsync` lọc khoảng ngày, nhóm theo phòng, chọn đủ ngày và `COUNT(MaDatPhong)=0`. Chuẩn hóa join cho tra cứu phòng. |
| `vw_KiemTraLichBooking` | Kiểm tra số phòng, ngày nhận/trả, đủ ngày liên tục và đối chiếu `DATPHONG_PHONG`; trả cờ `LichHopLe`. | Dùng nội bộ bởi view đối soát và procedure nhận/trả/no-show. Đây là quy tắc xuyên nhiều dòng, không thể thay bằng một constraint đơn giản. |
| `vw_BookingChoNhanPhong` | Booking `Đã đặt`, tổng hợp lịch, số phòng/đêm, cờ `CoTheNhanPhong`. | Màn hình chờ nhận phòng; ngăn nhận booking thiếu lịch, sai ngày, trùng với khách đang ở hoặc thiếu tổng tiền. |
| `vw_KhachDangLuuTru` | Booking `Đang ở`, phòng đang giữ, ngày trả dự kiến, số đêm, cờ trả hôm nay/quá hạn. | Màn hình khách đang lưu trú và theo dõi trả muộn. |
| `vw_GiamSat_LichPhong` | Chi tiết từng phòng-ngày, kèm booking, khách và trạng thái. | Màn hình lịch phòng; hiển thị trực tiếp ô trống/đã giữ và người giữ. |
| `vw_LichSuGiaoDichBooking` | Lịch sử thu/hoàn, số tiền quy đổi và cờ giao dịch bất thường. | Màn hình lịch sử giao dịch; thống nhất dữ liệu đọc và quy tắc nhận diện lỗi. |
| `vw_QuyetToanBooking` | Tổng hợp phải trả, đã thu, đã hoàn, thanh toán ròng, còn thu/cần hoàn và trạng thái đối soát. | Màn hình booking & công nợ; quyết định số tiền cọc, thanh toán, hoàn tiền và no-show. |
| `vw_BaoCao_DoanhThu_LoaiPhong` | Doanh thu theo loại. Booking mới lấy snapshot; booking cũ phân bổ ước tính theo giá cơ bản. | Báo cáo doanh thu; `SoBookingUocTinh` cho biết phần dữ liệu không có snapshot. |

Ứng dụng gọi 7 view trong `HotelService.ViewAsync`; `vw_TraCuuPhong` được gọi bởi `SearchRoomsAsync`, còn `vw_KiemTraLichBooking` chủ yếu là view dùng chung cho procedure/view khác.

## 6. Stored procedure nghiệp vụ production

| Procedure | Tác dụng | Dùng khi nào | Vì sao cần procedure |
|---|---|---|---|
| `sp_ThemKhachHang` | Validate và thêm khách với mã caller cung cấp; trả bản ghi vừa tạo. | Khi đã có `MaKH`. | Quy tắc format/độ dài và lỗi trùng mã thống nhất ở server. |
| `sp_TaoKhachHangTuThongTin` | Validate, sinh mã `KHxxxxxxxx` từ sequence và insert khách. | Khi đặt phòng chưa chọn khách cũ. | Gộp sinh mã và insert nguyên tử. |
| `sp_ThemLoaiPhong` | Thêm loại phòng và giá cơ bản, kiểm tra mã/tên/giá. | Quản trị danh mục. | Bảo vệ dữ liệu dù có client khác ngoài Blazor. |
| `sp_CapNhatGiaLoaiPhong` | Cập nhật giá, bắt buộc loại tồn tại và giá không âm. | Điều chỉnh giá. | Booking cũ vẫn giữ giá nhờ snapshot. |
| `sp_DatPhong` | Nhận TVP danh sách phòng; validate; khóa phòng theo thứ tự mã; tạo booking, snapshot và chiếm đủ dòng lịch. | Đặt phòng thật từ UI. | Transaction, lock và kiểm tra số dòng cập nhật ngăn overbooking và deadlock vòng tròn. |
| `sp_NhanPhong` | Kiểm tra version/trạng thái/lịch, chuyển `Đã đặt` → `Đang ở`. | Khách đến nhận phòng. | Chỉ cho phép chuyển trạng thái hợp lệ và chống xử lý trùng. |
| `sp_DatCoc` | Kiểm tra số dư, ghi giao dịch `Đặt cọc`, tăng version. | Thu tiền trước khi nhận phòng. | Không thu vượt tổng tiền và giữ lịch sử giao dịch. |
| `sp_TraPhong` | Kiểm tra đang ở, thu đủ phần còn lại, giải phóng lịch, chuyển `Đã trả`, lưu ngày trả. | Checkout. | Đảm bảo thanh toán và giải phóng phòng cùng transaction. |
| `sp_HuyBooking` | Hủy booking `Đã đặt`, hoàn đúng tiền đã thu, giải phóng lịch, chuyển `Đã hủy`. | Hủy trước khi nhận phòng. | Giữ audit hoàn tiền và ngăn hủy booking đã nhận. |
| `sp_NoShow_NhaPhong` | Sau ngày nhận dự kiến, ghi hoàn phần còn lại, lưu phí no-show, giải phóng phòng, chuyển `No-show`. | Khách không đến. | Tiền, trạng thái và lịch được cập nhật nguyên tử. |
| `SP_KhoiTao_LuoiNgay` | Sinh dòng `PHONG_NGAY` còn thiếu; dùng `sp_getapplock`. | Cài đặt/nạp thêm lịch; installer gọi 366 ngày. | Có sẵn ô lịch để booking chiếm và tránh hai tiến trình khởi tạo trùng. |

Các procedure chính dùng `XACT_ABORT ON`, transaction và rollback khi lỗi. Nhiều procedure từ chối chạy khi caller đã mở transaction để tránh transaction lồng khó kiểm soát.

### 6.1. Kỹ thuật chống tranh chấp và xung đột theo từng procedure

| Procedure | Kỹ thuật đang sử dụng | Tranh chấp/xung đột được xử lý | Lưu ý deadlock |
|---|---|---|---|
| `sp_ThemKhachHang` | Insert một lần và để primary key xử lý trùng; bắt lỗi `2601/2627`; từ chối transaction ngoài. | Hai request cùng dùng một `MaKH` không tạo hai khách; chỉ một insert thành công. | Không tự khóa trước bằng `IF EXISTS`, nên giảm race giữa bước kiểm tra và insert. |
| `sp_TaoKhachHangTuThongTin` | `SEQUENCE`, vòng lặp kiểm tra mã với `UPDLOCK, HOLDLOCK`, insert trong cùng ngữ cảnh transaction. | Tránh sinh trùng mã khách khi nhiều request đồng thời. | Vòng lặp thường chỉ lặp khi mã đã tồn tại; nên giữ transaction ngắn. |
| `sp_ThemLoaiPhong` | Dựa vào primary key và bắt lỗi duplicate; `XACT_ABORT ON`. | Hai thao tác thêm cùng mã loại phòng không tạo dữ liệu trùng. | Không có nhiều tài nguyên cần khóa nên nguy cơ deadlock thấp. |
| `sp_CapNhatGiaLoaiPhong` | `UPDATE` theo khóa chính, kiểm tra đúng một dòng qua `@@ROWCOUNT`. | Không cập nhật nhầm loại; lỗi khi loại không tồn tại. | Không dùng `Version` cho loại phòng; nếu cần chỉnh giá đồng thời nên bổ sung rowversion/version hoặc quy tắc ghi đè rõ ràng. |
| `sp_DatPhong` | Transaction nguyên tử; khóa các dòng `PHONG` bằng `UPDLOCK, HOLDLOCK`; khóa theo thứ tự tăng dần `MaPhong`; cập nhật `PHONG_NGAY` chỉ khi `MaDatPhong IS NULL`; kiểm tra số dòng cập nhật phải bằng `số phòng × số đêm`; TVP có khóa chính loại trùng phòng. | Ngăn hai booking cùng chiếm một phòng/ngày; rollback toàn bộ nếu thiếu lịch hoặc có phòng đã bị giữ; không cho cùng phòng xuất hiện hai lần trong một request. | Thứ tự khóa cố định là kỹ thuật chính để phá vòng chờ A giữ P101 chờ P102 / B giữ P102 chờ P101. Procedure demo `sp_DatPhong_Deadlock` cố ý bỏ quy tắc này. |
| `sp_NhanPhong` | Khóa booking bằng `UPDLOCK, HOLDLOCK`; kiểm tra `Version`; khóa các dòng lịch liên quan; kiểm tra `vw_KiemTraLichBooking`; cập nhật trạng thái trong transaction. | Hai nhân viên không thể cùng nhận một booking với cùng version; booking sai lịch không được nhận. | Nên duy trì cùng thứ tự truy cập tài nguyên giữa các procedure liên quan để giảm lock cycle. |
| `sp_DatCoc` | Khóa booking và các giao dịch bằng `UPDLOCK, HOLDLOCK`; tính `DaThuRong` trong transaction; tự sinh mã giao dịch; cập nhật `Version` theo điều kiện trạng thái/version; rollback khi lỗi. | Không cho hai request cùng thu vượt số tiền còn phải trả; request cũ bị từ chối nếu booking đã thay đổi. | Khóa booking trước rồi đến thanh toán là thứ tự cần giữ thống nhất với các SP tài chính khác. |
| `sp_TraPhong` | Khóa booking và lịch; kiểm tra trạng thái/version/lịch; giải phóng lịch, ghi thanh toán và đổi trạng thái trong cùng transaction; kiểm tra `@@ROWCOUNT`. | Không thể vừa trả phòng hai lần; không để trạng thái đã trả nhưng thiếu thanh toán hoặc lịch vẫn bị giữ khi transaction thành công. | Có thể bị chờ lock hợp lệ khi booking đang được thao tác; caller cần xử lý timeout/deadlock và tải lại version. |
| `sp_HuyBooking` | Khóa booking; kiểm tra version và trạng thái; tùy chọn kiểm tra khách thực hiện; tính tiền đã thu; ghi hoàn tiền; giải phóng lịch và đổi trạng thái nguyên tử. | Không hủy nhầm booking đã nhận; không hoàn sai số tiền; hai thao tác hủy cạnh tranh chỉ một thao tác thắng version. | Cần giữ thứ tự booking → lịch → thanh toán nhất quán với `sp_TraPhong` và `sp_NoShow_NhaPhong`. |
| `sp_NoShow_NhaPhong` | Khóa booking, lịch và giao dịch bằng `UPDLOCK, HOLDLOCK`; kiểm tra ngày nhận đã qua; xác minh phí phạt + tiền hoàn = tiền thu ròng; ghi hoàn tiền, giải phóng lịch và tăng version trong transaction. | Tránh xử lý no-show hai lần, hoàn vượt tiền đã thu hoặc giải phóng lịch của booking có dữ liệu sai. | Đây là procedure giữ nhiều loại tài nguyên; thứ tự khóa phải thống nhất với các thao tác hủy/trả phòng. |
| `SP_KhoiTao_LuoiNgay` | Dùng `sp_getapplock` trên resource `HotelDesk.GenerateCalendar`; chỉ insert những cặp phòng-ngày còn thiếu; transaction/rollback khi lỗi. | Hai tiến trình khởi tạo lịch không cùng lúc sinh trùng hoặc tranh chấp cùng vùng dữ liệu. | Application lock là khóa logic cấp database; cần bảo đảm mọi luồng khởi tạo đều dùng cùng tên resource. |

### 6.2. Kỹ thuật và giới hạn của từng view

View không tự mở transaction và không tự sở hữu lock lâu dài; nó là lớp truy vấn. Việc tránh xung đột ghi chủ yếu nằm ở procedure gọi view và isolation level của câu lệnh. Tuy vậy, từng view có các kỹ thuật giúp giảm đọc sai hoặc phát hiện dữ liệu không nhất quán:

| View | Kỹ thuật liên quan đến nhất quán/concurrency | Ý nghĩa |
|---|---|---|
| `vw_TraCuuPhong` | Đọc cùng một nguồn lịch `PHONG_NGAY`; phía production lọc đủ số dòng theo `COUNT_BIG(*)` và `COUNT(MaDatPhong)=0`. | Kết quả chỉ coi phòng là trống khi có đủ toàn bộ đêm và không có ngày bị chiếm. Tuy nhiên đây là read-then-write; việc bảo vệ cuối cùng phải do `sp_DatPhong`. |
| `vw_KiemTraLichBooking` | Đối chiếu số phòng, ngày đầu/cuối, tính liên tục và snapshot chi tiết. | Phát hiện lịch thiếu, đứt ngày, khác số phòng hoặc khác snapshot trước khi procedure tiếp tục. View không khóa dữ liệu nên vẫn cần gọi trong transaction có lock. |
| `vw_BookingChoNhanPhong` | Dùng CTE tổng hợp theo phòng/booking, tham chiếu `vw_KiemTraLichBooking`, kiểm tra booking khác đang `Đang ở`. | Không giải quyết tranh chấp ghi, nhưng loại các booking không đủ điều kiện khỏi danh sách có thể nhận phòng. Procedure `sp_NhanPhong` kiểm tra lại để tránh TOCTOU. |
| `vw_KhachDangLuuTru` | Tính ngày trả, quá hạn và lịch thiếu từ dữ liệu hiện tại; dùng `GETDATE()`. | Cung cấp trạng thái đọc nhất quán theo thời điểm truy vấn. Không giữ phòng và không ngăn thao tác trả/hủy đồng thời. |
| `vw_GiamSat_LichPhong` | Đọc chi tiết từng dòng lịch bằng `LEFT JOIN` tới booking/khách. | Phục vụ quan sát, không ghi dữ liệu và không đặt lock nghiệp vụ. Nếu cần snapshot tuyệt đối cho báo cáo dài, caller nên dùng transaction/isolation phù hợp. |
| `vw_LichSuGiaoDichBooking` | Tính hướng thu/hoàn và gắn cờ giao dịch bất thường thay vì sửa dữ liệu. | Phát hiện giao dịch sai để procedure tài chính từ chối xử lý; không tự khóa hay tự sửa giao dịch. |
| `vw_QuyetToanBooking` | Gom giao dịch theo booking, tính thanh toán ròng, kiểm tra giao dịch bất thường, tiền hoàn vượt tiền thu và trạng thái no-show. | Tránh để mỗi màn hình tự tính công nợ khác nhau. Đây là lớp phát hiện, còn `sp_DatCoc`, `sp_TraPhong`, `sp_HuyBooking`, `sp_NoShow_NhaPhong` mới khóa và ghi dữ liệu. |
| `vw_BaoCao_DoanhThu_LoaiPhong` | Dùng snapshot bất biến cho booking mới; dữ liệu legacy được đánh dấu `UocTinh=1`; phân bổ phần làm tròn vào một dòng để tổng không lệch. | Tránh báo cáo thay đổi do giá danh mục hiện tại; phân biệt số thật và số ước tính. View chỉ đọc nên không chống xung đột cập nhật. |

### 6.3. Các demo cố ý vi phạm nguyên tắc an toàn

- `sp_DatPhong_KhongBaoVe` mô phỏng race condition: hai phiên có thể cùng đọc phòng trống trước khi ghi. Đây là lý do production không được tách kiểm tra phòng trống và thao tác chiếm phòng thành hai request độc lập.
- `sp_DatPhong_Deadlock` khóa phòng theo thứ tự client gửi và dùng `WAITFOR`; hai phiên gửi thứ tự ngược nhau sẽ tạo vòng chờ. `sp_DatPhong` production khắc phục bằng `ORDER BY MaPhong` khi lấy lock.
- `sp_TraCuuPhongTrong_DirtyRead` dùng `READ UNCOMMITTED`, có thể đọc thay đổi chưa commit. Đây chỉ phù hợp demo isolation level, không phù hợp quyết định đặt phòng.
- `sp_TraPhongDemo` cố ý giải phóng lịch rồi ném lỗi sau thời gian chờ để chứng minh transaction rollback sẽ khôi phục dữ liệu.

### 6.4. Nguyên tắc vận hành nên giữ

1. Không thực hiện luồng “đọc còn trống ở UI rồi tự `INSERT/UPDATE` bảng” cho nghiệp vụ đặt phòng; phải gọi procedure transaction.
2. Mọi procedure cùng nghiệp vụ cần khóa tài nguyên theo cùng thứ tự, ưu tiên booking/phòng theo một quy ước thống nhất.
3. Giữ transaction ngắn, không gọi API ngoài, không chờ người dùng và không dùng `WAITFOR` trong luồng production.
4. Khi gặp lỗi version, timeout hoặc deadlock victim 1205, UI nên tải lại view và cho người dùng xác nhận lại; không tự động lặp vô hạn một thao tác có thể tạo giao dịch trùng.
5. Theo dõi deadlock graph, thời gian chờ lock và số lần retry trong production để phát hiện index hoặc thứ tự truy cập chưa phù hợp.

## 7. Procedure/demo không phải nghiệp vụ chính

| Object | Mục đích |
|---|---|
| `sp_DatPhong_KhongBaoVe` | Cố ý thiếu cơ chế bảo vệ race condition; nút “Đặt phòng lỗi” dùng để minh họa overbooking. |
| `sp_DatPhong_Deadlock` | Khóa theo thứ tự caller gửi và chờ 5 giây để minh họa deadlock SQL Server 1205. |
| `sp_TraCuuPhongTrong_DirtyRead` | Dùng `READ UNCOMMITTED` để minh họa đọc dữ liệu chưa commit. |
| `sp_TraPhongDemo` | Giải phóng lịch, chờ rồi ném lỗi để minh họa rollback/dirty read. |
| Các object cũ bị drop | `sp_Web_DatHaiPhong`, `sp_Booking_TaoMoi`, `vw_TraCuuPhongTrong_HomNay`, `vw_GiamSat_TrangThaiDatPhong` đã bị loại trong `schema/02_remove_replaced_objects.sql`. |

## 8. Luồng sử dụng từ ứng dụng

1. Tra cứu phòng: `vw_TraCuuPhong` → lọc đủ ngày và ngày chưa bị chiếm.
2. Tạo booking: có thể gọi `sp_TaoKhachHangTuThongTin` → `sp_DatPhong`.
3. Màn hình booking đọc `vw_QuyetToanBooking`; action gọi `sp_NhanPhong`, `sp_DatCoc`, `sp_TraPhong`, `sp_HuyBooking` hoặc `sp_NoShow_NhaPhong`.
4. Arrivals/stays/calendar/transactions/revenue đọc các view chuyên biệt.
5. Thao tác cập nhật gửi `Version`; nếu có thay đổi trước đó, procedure báo stale version và UI yêu cầu tải lại.

## 9. Nhận xét và khuyến nghị

### Điểm tốt

- Nghiệp vụ quan trọng nằm trong transaction ở database.
- Có optimistic concurrency, khóa theo thứ tự cố định và kiểm tra số dòng cập nhật.
- `DATPHONG_PHONG` bảo toàn lịch sử giá; báo cáo doanh thu nhận diện dữ liệu ước tính legacy.
- Thanh toán là append-only ledger, thuận lợi cho audit và đối soát.
- Có index vào hai truy vấn nóng: lịch theo booking và giao dịch theo booking.

### Rủi ro/cần cải thiện

1. **Encoding:** nhiều file SQL và text C# hiển thị mojibake như `ÄÃ£`, cho thấy encoding không thống nhất. Cần chuẩn hóa UTF-8 và kiểm tra lại literal trạng thái/giao dịch; nếu không, so sánh tiếng Việt có thể không khớp dữ liệu thực.
2. **Ràng buộc còn thiếu:** nên bổ sung CHECK cho giá, tiền thanh toán, loại giao dịch và trạng thái; cân nhắc unique cho CCCD/số điện thoại nếu nghiệp vụ yêu cầu.
3. **Waitlist chưa hoàn chỉnh:** cần procedure/UI thêm, đổi trạng thái và tìm khách khi phòng trống, hoặc ghi rõ là tính năng chưa triển khai.
4. **Độ dài mã giao dịch:** schema nâng `THANHTOAN.MaGD` lên 30 ký tự nhưng một số procedure nhận `VARCHAR(MAX)` rồi validate tối đa 10. Nên thống nhất quy ước mã.
5. **Cài đặt database/demo:** cần tài liệu hóa rõ script cho `QL_KhachSan` và `QL_KhachSan_Demo`, tránh chạy nhầm `USE`.
6. **Ngày hiện tại:** view dùng `GETDATE()`/`SYSDATETIME()`, gây khó test lặp lại; nên hỗ trợ ngày tham chiếu trong test/report.
7. **Bảo mật:** cấp quyền `EXECUTE` trên procedure và `SELECT` trên view, hạn chế ghi trực tiếp vào bảng.
8. **Kiểm thử:** nên tự động hóa test race booking, nhận/trả đồng thời, retry, hoàn tiền, no-show và booking legacy thiếu `DATPHONG_PHONG`.

## 10. Kết luận

Thiết kế hiện tại phù hợp với một hệ thống booking khách sạn nhỏ có yêu cầu minh họa concurrency. `DATPHONG`, `PHONG_NGAY`, `THANHTOAN` và các procedure transaction là lõi đảm bảo tính đúng đắn; các view tạo lớp đọc cho từng màn hình; `DATPHONG_PHONG` bảo toàn lịch sử giá. Trước khi vận hành rộng hơn, nên ưu tiên xử lý encoding, bổ sung constraint nghiệp vụ, chuẩn hóa script triển khai và hoàn thiện hoặc đánh dấu rõ waitlist cùng các demo object.

## 11. Hướng dẫn chạy dự án bằng Docker

### 11.1. Yêu cầu

- Docker Desktop đã cài và đang chạy.
- Docker Compose v2, sử dụng lệnh `docker compose`.
- Cổng `1433` và `8080` trên máy chưa bị chương trình khác sử dụng.
- Có thể chạy lệnh tại thư mục gốc chứa `docker-compose.yml`.

### 11.2. Cấu hình mật khẩu SQL Server

Tạo file `.env` từ file mẫu:

PowerShell:

```powershell
Copy-Item .env.example .env
```

Mở `.env` và đặt `MSSQL_SA_PASSWORD`. Mật khẩu cần đáp ứng chính sách SQL Server, tối thiểu 8 ký tự và nên có chữ hoa, chữ thường, số, ký tự đặc biệt. Có thể bật/tắt các chức năng demo bằng:

```env
MSSQL_SA_PASSWORD=HotelDesk_Dev2026!
DEMO_ENABLED=false
```

Không commit file `.env` thật lên Git vì file này chứa mật khẩu tài khoản `sa`.

### 11.3. Build và khởi động toàn bộ hệ thống

Từ thư mục gốc dự án chạy:

```powershell
docker compose up -d --build
```

Compose khởi động theo thứ tự:

1. `db`: SQL Server 2022 Developer, lưu dữ liệu trong volume `mssql_data`.
2. `db-init`: chờ database healthy, tạo `QL_KhachSan` nếu chưa có, sau đó chạy `00_create_new_database.sql` và `01_install_views_and_procedures.sql`.
3. `hoteldesk`: build ứng dụng .NET 8 và kết nối tới SQL Server bằng hostname nội bộ `db`.

Sau khi hoàn tất, mở:

```text
http://localhost:8080
```

Ứng dụng dùng connection string trong `docker-compose.yml`; `appsettings.json` để trống connection string khi chạy container là bình thường.

### 11.4. Kiểm tra trạng thái và log

Xem trạng thái các service:

```powershell
docker compose ps
```

Xem log khởi tạo database:

```powershell
docker compose logs db-init
```

Xem log ứng dụng:

```powershell
docker compose logs -f hoteldesk
```

Nếu `db-init` không thành công, xem thêm log SQL Server:

```powershell
docker compose logs db
```

`hoteldesk` chỉ được start khi `db-init` kết thúc thành công, vì vậy cần xử lý lỗi database trước khi kiểm tra UI.

### 11.5. Dừng và chạy lại

Dừng container nhưng giữ nguyên dữ liệu SQL Server:

```powershell
docker compose stop
```

Khởi động lại:

```powershell
docker compose start
```

Hoặc dừng và xóa container/network nhưng vẫn giữ volume dữ liệu:

```powershell
docker compose down
docker compose up -d
```

Khi database đã tồn tại, `db-init` sẽ bỏ qua bước tạo database gốc nhưng vẫn chạy lại script cài đặt view/procedure. Các script hiện được thiết kế theo hướng `IF EXISTS`/`CREATE OR ALTER` cho phần lớn object.

### 11.6. Reset toàn bộ database Docker

Chỉ dùng khi muốn xóa dữ liệu local và tạo lại database từ đầu:

```powershell
docker compose down -v
docker compose up -d --build
```

`-v` sẽ xóa volume `mssql_data`, đồng nghĩa xóa toàn bộ booking, khách hàng, thanh toán và dữ liệu test trong database Docker. Không dùng lệnh này trên môi trường có dữ liệu cần giữ.

### 11.7. Kết nối SQL Server từ máy host

Nếu cần dùng SSMS/Azure Data Studio kết nối trực tiếp:

```text
Server: localhost,1433
Database: QL_KhachSan
User: sa
Password: giá trị MSSQL_SA_PASSWORD trong .env
Encrypt: False hoặc Trust Server Certificate: True
```

Từ container ứng dụng, server phải là `db`, không phải `localhost`; đây là lý do connection string trong Compose dùng `Server=db`.

### 11.8. Sự cố thường gặp

- **Cổng 8080/1433 đã được sử dụng:** đổi phần bên trái trong `ports`, ví dụ `8081:8080` để truy cập ứng dụng tại `http://localhost:8081`; nếu đổi cổng SQL Server thì dùng cổng mới khi kết nối từ host.
- **Mật khẩu không đạt chính sách:** sửa `MSSQL_SA_PASSWORD` trong `.env`, sau đó chạy `docker compose down -v` rồi khởi động lại nếu SQL Server đã khởi tạo volume lỗi.
- **`db-init` báo database đã tồn tại nhưng thiếu object:** chạy `docker compose up --build db-init`; nếu schema bị hỏng hoặc dữ liệu chỉ là dữ liệu local có thể reset bằng `down -v`.
- **Ứng dụng không mở được:** kiểm tra `docker compose ps` và `docker compose logs hoteldesk`; kiểm tra tiếp `db-init` vì ứng dụng phụ thuộc service này.
- **Thay đổi mã nguồn không xuất hiện:** cần build lại image bằng `docker compose up -d --build`; thay đổi chỉ ở SQL có thể build/chạy lại `db-init`.
