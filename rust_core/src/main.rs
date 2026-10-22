//! Sora Core - the small native half of Sora PoS.
//!
//! Everything the Flutter screens cannot do by themselves lives here:
//! listing and talking to Windows printers (raw ESC/POS), the native file
//! dialogs, Windows Credential Manager, spreadsheet reading, and swapping the
//! taskbar icon when the shop changes theme.
//!
//! Each command prints one JSON object to stdout. Errors go to stderr.

use std::collections::HashMap;
use std::env;
use std::ffi::c_void;
use std::fs;
use std::ptr::{null, null_mut};

use serde::Serialize;
use serde_json::json;
use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::Graphics::Dwm::DwmSetWindowAttribute;
use windows_sys::Win32::Graphics::Printing::{
    ClosePrinter, EndDocPrinter, EndPagePrinter, EnumPrintersW, OpenPrinterW, StartDocPrinterW,
    StartPagePrinter, WritePrinter, DOC_INFO_1W, PRINTER_ENUM_CONNECTIONS, PRINTER_ENUM_LOCAL,
    PRINTER_HANDLE, PRINTER_INFO_4W,
};
use windows_sys::Win32::Security::Credentials::{
    CredDeleteW, CredFree, CredReadW, CredWriteW, CREDENTIALW, CRED_PERSIST_LOCAL_MACHINE,
    CRED_TYPE_GENERIC,
};
use windows_sys::Win32::UI::Controls::Dialogs::{
    GetOpenFileNameW, GetSaveFileNameW, OPENFILENAMEW, OFN_FILEMUSTEXIST, OFN_HIDEREADONLY,
    OFN_OVERWRITEPROMPT, OFN_PATHMUSTEXIST,
};
use windows_sys::Win32::UI::Shell::ShellExecuteW;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    FindWindowW, LoadImageW, SendMessageW, ICON_BIG, ICON_SMALL, IMAGE_ICON, LR_LOADFROMFILE,
    WM_SETICON,
};

type BoxErr = Box<dyn std::error::Error>;

fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), BoxErr> {
    let args: Vec<String> = env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("help");
    match cmd {
        "printers" => printers(),
        "print_raw" => {
            let printer = args.get(1).ok_or("missing printer")?;
            let file = args.get(2).ok_or("missing file")?;
            print_raw(printer, file)
        }
        "open_dialog" => {
            let title = args.get(1).map(String::as_str).unwrap_or("Open");
            let filter = args.get(2).map(String::as_str).unwrap_or("All files|*.*");
            open_dialog(title, filter)
        }
        "save_dialog" => {
            let title = args.get(1).map(String::as_str).unwrap_or("Save");
            let default_name = args.get(2).map(String::as_str).unwrap_or("sora-export.json");
            let filter = args.get(3).map(String::as_str).unwrap_or("All files|*.*");
            save_dialog(title, default_name, filter)
        }
        "import_preview" => {
            let file = args.get(1).ok_or("missing file")?;
            import_preview(file)
        }
        "import_products" => {
            let file = args.get(1).ok_or("missing file")?;
            let map = args.get(2).ok_or("missing mapping")?;
            import_products(file, map)
        }
        "cred_set" => {
            let target = args.get(1).ok_or("missing target")?;
            let value = args.get(2).ok_or("missing value")?;
            cred_set(target, value)
        }
        "cred_get" => {
            let target = args.get(1).ok_or("missing target")?;
            cred_get(target)
        }
        "cred_delete" => {
            let target = args.get(1).ok_or("missing target")?;
            cred_delete(target)
        }
        "set_window_icon" => {
            let ico = args.get(1).ok_or("missing icon")?;
            set_window_icon(ico)
        }
        "set_caption" => {
            let hex = args.get(1).ok_or("missing colour")?;
            set_caption(hex)
        }
        "print_pdf" => {
            let file = args.get(1).ok_or("missing file")?;
            let printer = args.get(2).map(String::as_str).unwrap_or("");
            print_pdf(file, printer)
        }
        "open_file" => {
            let path = args.get(1).ok_or("missing path")?;
            open_file(path)
        }
        "version" => {
            println!("{}", json!({ "version": env!("CARGO_PKG_VERSION") }));
            Ok(())
        }
        _ => {
            println!(
                "{}",
                json!({
                    "name": "sora_core",
                    "version": env!("CARGO_PKG_VERSION"),
                    "commands": ["printers","print_raw","open_dialog","save_dialog",
                        "import_preview","import_products","cred_set","cred_get",
                        "cred_delete","set_window_icon","open_file","set_caption","print_pdf","version"]
                })
            );
            Ok(())
        }
    }
}

fn json<T: Serialize>(value: T) -> String {
    serde_json::to_string(&value).unwrap_or_else(|_| "{}".into())
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn app_window() -> HWND {
    let class = wide("FLUTTER_RUNNER_WIN32_WINDOW");
    unsafe { FindWindowW(class.as_ptr(), null()) }
}

// ---------------------------------------------------------------- printers

#[derive(Serialize)]
struct PrinterList {
    printers: Vec<String>,
    default: Option<String>,
}

fn printers() -> Result<(), BoxErr> {
    let flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    let mut needed = 0u32;
    let mut returned = 0u32;
    unsafe {
        EnumPrintersW(flags, null(), 4, null_mut(), 0, &mut needed, &mut returned);
    }
    if needed == 0 {
        println!("{}", json(PrinterList { printers: vec![], default: None }));
        return Ok(());
    }
    let mut buf = vec![0u8; needed as usize];
    let ok = unsafe {
        EnumPrintersW(
            flags,
            null(),
            4,
            buf.as_mut_ptr(),
            needed,
            &mut needed,
            &mut returned,
        )
    };
    if ok == 0 {
        return Err("EnumPrinters failed".into());
    }
    let mut printers = Vec::new();
    unsafe {
        let items = buf.as_ptr() as *const PRINTER_INFO_4W;
        for i in 0..returned as usize {
            let name_ptr = (*items.add(i)).pPrinterName;
            if !name_ptr.is_null() {
                printers.push(pcwstr_to_string(name_ptr));
            }
        }
    }
    printers.sort_by_key(|s| s.to_lowercase());
    println!(
        "{}",
        json(PrinterList {
            printers,
            default: default_printer(),
        })
    );
    Ok(())
}

fn default_printer() -> Option<String> {
    // The default queue's name is kept in the user's printer connection record;
    // a cheap and reliable route is the Win32 profile call, but for a small
    // offline app the first local queue is a sane fallback. Read it from the
    // registry so a machine with hundreds of queues still answers instantly.
    use std::process::Command;
    let out = Command::new("reg")
        .args([
            "query",
            r"HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows",
            "/v",
            "Device",
        ])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let line = text.lines().find(|l| l.contains("Device"))?;
    let value = line.split("REG_SZ").nth(1).unwrap_or("").trim();
    let name = value.split(',').next()?.trim();
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

unsafe fn pcwstr_to_string(ptr: *const u16) -> String {
    let mut len = 0usize;
    while *ptr.add(len) != 0 {
        len += 1;
    }
    String::from_utf16_lossy(std::slice::from_raw_parts(ptr, len))
}

fn print_raw(printer: &str, file: &str) -> Result<(), BoxErr> {
    let data = fs::read(file)?;
    let name = wide(printer);
    let mut handle = PRINTER_HANDLE::default();
    let ok = unsafe { OpenPrinterW(name.as_ptr(), &mut handle, null()) };
    if ok == 0 {
        return Err(format!("Could not open printer '{printer}'").into());
    }
    let doc_name = wide("Sora PoS receipt");
    let raw = wide("RAW");
    let doc = DOC_INFO_1W {
        pDocName: doc_name.as_ptr() as *mut u16,
        pOutputFile: null_mut(),
        pDatatype: raw.as_ptr() as *mut u16,
    };
    let started = unsafe { StartDocPrinterW(handle, 1, &doc) };
    if started == 0 {
        unsafe {
            ClosePrinter(handle);
        }
        return Err(format!("Printer '{printer}' refused the job").into());
    }
    unsafe {
        StartPagePrinter(handle);
        let mut written = 0u32;
        WritePrinter(
            handle,
            data.as_ptr() as *const c_void,
            data.len() as u32,
            &mut written,
        );
        EndPagePrinter(handle);
        EndDocPrinter(handle);
        ClosePrinter(handle);
    }
    println!("{}", json!({ "printed": true, "bytes": data.len() }));
    Ok(())
}

// ----------------------------------------------------------------- dialogs

fn parse_filter(filter: &str) -> Vec<u16> {
    // "Spreadsheets|*.xlsx;*.csv|All files|*.*" -> UTF-16 double-null list.
    let mut out = Vec::new();
    for part in filter.split('|') {
        out.extend(part.encode_utf16());
        out.push(0);
    }
    out.push(0);
    out
}

fn open_dialog(title: &str, filter: &str) -> Result<(), BoxErr> {
    let mut file_buf = vec![0u16; 32768];
    let title_w = wide(title);
    let filter_w = parse_filter(filter);
    let mut ofn: OPENFILENAMEW = unsafe { std::mem::zeroed() };
    ofn.lStructSize = std::mem::size_of::<OPENFILENAMEW>() as u32;
    ofn.hwndOwner = app_window();
    ofn.lpstrFilter = filter_w.as_ptr();
    ofn.lpstrFile = file_buf.as_mut_ptr();
    ofn.nMaxFile = file_buf.len() as u32;
    ofn.lpstrTitle = title_w.as_ptr();
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;
    let ok = unsafe { GetOpenFileNameW(&mut ofn) };
    if ok == 0 {
        println!("{}", json!({ "path": null }));
        return Ok(());
    }
    let end = file_buf.iter().position(|&c| c == 0).unwrap_or(0);
    let path = String::from_utf16_lossy(&file_buf[..end]);
    println!("{}", json!({ "path": path }));
    Ok(())
}

fn save_dialog(title: &str, default_name: &str, filter: &str) -> Result<(), BoxErr> {
    let mut file_buf = vec![0u16; 32768];
    let name: Vec<u16> = default_name.encode_utf16().collect();
    for (i, c) in name.iter().take(file_buf.len() - 1).enumerate() {
        file_buf[i] = *c;
    }
    let title_w = wide(title);
    let filter_w = parse_filter(filter);
    let ext = default_name
        .rsplit_once('.')
        .map(|(_, e)| wide(e))
        .unwrap_or_else(|| wide(""));
    let mut ofn: OPENFILENAMEW = unsafe { std::mem::zeroed() };
    ofn.lStructSize = std::mem::size_of::<OPENFILENAMEW>() as u32;
    ofn.hwndOwner = app_window();
    ofn.lpstrFilter = filter_w.as_ptr();
    ofn.lpstrFile = file_buf.as_mut_ptr();
    ofn.nMaxFile = file_buf.len() as u32;
    ofn.lpstrTitle = title_w.as_ptr();
    ofn.lpstrDefExt = if ext.len() > 1 { ext.as_ptr() } else { null() };
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_HIDEREADONLY;
    let ok = unsafe { GetSaveFileNameW(&mut ofn) };
    if ok == 0 {
        println!("{}", json!({ "path": null }));
        return Ok(());
    }
    let end = file_buf.iter().position(|&c| c == 0).unwrap_or(0);
    let path = String::from_utf16_lossy(&file_buf[..end]);
    println!("{}", json!({ "path": path }));
    Ok(())
}

// -------------------------------------------------------------- spreadsheets

#[derive(Serialize)]
struct Preview {
    headers: Vec<String>,
    rows: Vec<Vec<String>>,
    total_rows: usize,
    mapping: HashMap<String, i64>,
    sheet: String,
}

fn read_table(path: &str) -> Result<(String, Vec<Vec<String>>), BoxErr> {
    let ext = std::path::Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    if ext == "csv" || ext == "txt" {
        let mut reader = csv::ReaderBuilder::new()
            .has_headers(false)
            .flexible(true)
            .from_path(path)?;
        let mut rows = Vec::new();
        for record in reader.records() {
            let record = record?;
            rows.push(record.iter().map(|s| s.trim().to_string()).collect());
        }
        let sheet = std::path::Path::new(path)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("CSV")
            .to_string();
        return Ok((sheet, rows));
    }

    use calamine::{open_workbook_auto, Reader};
    let mut workbook = open_workbook_auto(path)?;
    let names = workbook.sheet_names().to_owned();
    let sheet = names.first().cloned().unwrap_or_else(|| "Sheet1".into());
    let range = workbook
        .worksheet_range(&sheet)
        .map_err(|e| format!("Could not read sheet: {e}"))?;
    let mut rows = Vec::new();
    for row in range.rows() {
        let mut out: Vec<String> = row.iter().map(|c| c.to_string().trim().to_string()).collect();
        while out.last().map(|s| s.is_empty()).unwrap_or(false) {
            out.pop();
        }
        if !out.iter().all(|s| s.is_empty()) {
            rows.push(out);
        }
    }
    Ok((sheet, rows))
}

fn guess_mapping(headers: &[String]) -> HashMap<String, i64> {
    let mut map: HashMap<String, i64> = HashMap::new();
    let fields: [(&str, &[&str]); 6] = [
        ("name", &["product name", "item name", "name", "description", "product", "item", "title"]),
        ("sku", &["sku", "barcode", "bar code", "upc", "ean", "code", "item code"]),
        ("category", &["category", "department", "group", "type", "class"]),
        ("price", &["sell price", "selling price", "retail", "price", "sell", "amount"]),
        ("cost", &["cost", "buy price", "buying price", "supply price", "supplyprice", "purchase", "wholesale"]),
        ("stock", &["on hand", "in stock", "stock", "qty", "quantity", "inventory", "count"]),
    ];
    for (field, needles) in fields {
        let mut best: Option<(usize, i64)> = None;
        for (i, header) in headers.iter().enumerate() {
            let h = header.to_lowercase();
            for (rank, needle) in needles.iter().enumerate() {
                if h == *needle || h.contains(needle) {
                    let candidate = (rank, i as i64);
                    if best.map(|(r, _)| rank < r).unwrap_or(true) {
                        best = Some(candidate);
                    }
                    break;
                }
            }
        }
        // Cost must never steal the Price column.
        if field == "price" {
            if let Some(i) = map.get("cost") {
                if best.map(|(_, idx)| idx == *i).unwrap_or(false) {
                    best = None;
                }
            }
        }
        map.insert(field.to_string(), best.map(|(_, i)| i).unwrap_or(-1));
    }
    map
}

fn import_preview(path: &str) -> Result<(), BoxErr> {
    let (sheet, rows) = read_table(path)?;
    if rows.is_empty() {
        return Err("That file has no rows".into());
    }
    let headers: Vec<String> = rows[0]
        .iter()
        .enumerate()
        .map(|(i, h)| {
            if h.trim().is_empty() {
                format!("Column {}", i + 1)
            } else {
                h.clone()
            }
        })
        .collect();
    let mapping = guess_mapping(&headers);
    let body = rows.iter().skip(1).cloned().collect::<Vec<_>>();
    let preview = body.iter().take(40).cloned().collect::<Vec<_>>();
    println!(
        "{}",
        json(Preview {
            headers,
            rows: preview,
            total_rows: body.len(),
            mapping,
            sheet,
        })
    );
    Ok(())
}

#[derive(Serialize)]
struct ImportedProduct {
    name: String,
    sku: String,
    category: String,
    price: f64,
    cost: f64,
    stock: f64,
}

fn number(text: &str) -> f64 {
    let cleaned: String = text
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == '.' || *c == ',' || *c == '-')
        .collect();
    let cleaned = if cleaned.matches(',').count() == 1 && !cleaned.contains('.') {
        cleaned.replace(',', ".")
    } else {
        cleaned.replace(',', "")
    };
    cleaned.parse::<f64>().unwrap_or(0.0)
}

fn import_products(path: &str, mapping: &str) -> Result<(), BoxErr> {
    let parts: Vec<i64> = mapping
        .split(',')
        .map(|p| p.trim().parse::<i64>().unwrap_or(-1))
        .collect();
    let want = |field: usize| -> i64 { parts.get(field).copied().unwrap_or(-1) };
    let (name_i, sku_i, cat_i, price_i, cost_i, stock_i) =
        (want(0), want(1), want(2), want(3), want(4), want(5));
    let (_, rows) = read_table(path)?;
    let mut out: Vec<ImportedProduct> = Vec::new();
    for row in rows.iter().skip(1) {
        let get = |i: i64| -> String {
            if i < 0 {
                String::new()
            } else {
                row.get(i as usize).cloned().unwrap_or_default().trim().to_string()
            }
        };
        let name = get(name_i);
        if name.is_empty() {
            continue;
        }
        out.push(ImportedProduct {
            name,
            sku: get(sku_i),
            category: get(cat_i),
            price: number(&get(price_i)),
            cost: number(&get(cost_i)),
            stock: number(&get(stock_i)),
        });
    }
    println!("{}", json!({ "products": out }));
    Ok(())
}

// ------------------------------------------------------------- credentials

fn cred_set(target: &str, value: &str) -> Result<(), BoxErr> {
    let target_w = wide(target);
    let user_w = wide("Sora PoS");
    let mut blob = value.as_bytes().to_vec();
    let cred = CREDENTIALW {
        Flags: 0,
        Type: CRED_TYPE_GENERIC,
        TargetName: target_w.as_ptr() as *mut u16,
        Comment: null_mut(),
        LastWritten: Default::default(),
        CredentialBlobSize: blob.len() as u32,
        CredentialBlob: blob.as_mut_ptr(),
        Persist: CRED_PERSIST_LOCAL_MACHINE,
        AttributeCount: 0,
        Attributes: null_mut(),
        TargetAlias: null_mut(),
        UserName: user_w.as_ptr() as *mut u16,
    };
    let ok = unsafe { CredWriteW(&cred, 0) };
    if ok == 0 {
        return Err("Windows refused to save the password".into());
    }
    println!("{}", json!({ "saved": true }));
    Ok(())
}

fn cred_get(target: &str) -> Result<(), BoxErr> {
    let target_w = wide(target);
    let mut ptr: *mut CREDENTIALW = null_mut();
    let ok = unsafe { CredReadW(target_w.as_ptr(), CRED_TYPE_GENERIC, 0, &mut ptr) };
    if ok == 0 || ptr.is_null() {
        println!("{}", json!({ "value": null }));
        return Ok(());
    }
    let mut value = None;
    unsafe {
        let cred = &*ptr;
        if !cred.CredentialBlob.is_null() && cred.CredentialBlobSize > 0 {
            let bytes = std::slice::from_raw_parts(
                cred.CredentialBlob,
                cred.CredentialBlobSize as usize,
            );
            value = Some(String::from_utf8_lossy(bytes).to_string());
        }
        CredFree(ptr as *const c_void);
    }
    println!("{}", json!({ "value": value }));
    Ok(())
}

fn cred_delete(target: &str) -> Result<(), BoxErr> {
    let target_w = wide(target);
    unsafe {
        CredDeleteW(target_w.as_ptr(), CRED_TYPE_GENERIC, 0);
    }
    println!("{}", json!({ "deleted": true }));
    Ok(())
}

// ------------------------------------------------------------------- shell
// ------------------------------------------------------------------- shell

fn set_window_icon(ico: &str) -> Result<(), BoxErr> {
    let path = std::path::Path::new(ico).canonicalize()?;
    let path_w = wide(&path.to_string_lossy());
    let hwnd = app_window();
    if hwnd.is_null() {
        return Err("Sora PoS window not found".into());
    }
    let hicon = unsafe {
        LoadImageW(
            null_mut(),
            path_w.as_ptr(),
            IMAGE_ICON,
            0,
            0,
            LR_LOADFROMFILE,
        )
    };
    if hicon.is_null() {
        return Err("Could not load the theme icon".into());
    }
    unsafe {
        SendMessageW(hwnd, WM_SETICON, ICON_BIG as usize, hicon as isize);
        SendMessageW(hwnd, WM_SETICON, ICON_SMALL as usize, hicon as isize);
    }
    println!("{}", json!({ "icon": path.to_string_lossy() }));
    Ok(())
}

fn set_caption(hex: &str) -> Result<(), BoxErr> {
    let cleaned = hex.trim_start_matches('#');
    if cleaned.len() != 6 {
        return Err("caption colour must be RRGGBB".into());
    }
    let r = u8::from_str_radix(&cleaned[0..2], 16)?;
    let g = u8::from_str_radix(&cleaned[2..4], 16)?;
    let b = u8::from_str_radix(&cleaned[4..6], 16)?;
    let colorref: u32 = (b as u32) << 16 | (g as u32) << 8 | r as u32;
    let hwnd = app_window();
    if hwnd.is_null() {
        return Err("Sora PoS window not found".into());
    }
    let luminance = (0.299 * r as f64 + 0.587 * g as f64 + 0.114 * b as f64) / 255.0;
    let text: u32 = if luminance > 0.55 { 0x00202020 } else { 0x00F4F4F4 };
    let dark: u32 = if luminance > 0.55 { 0 } else { 1 };
    unsafe {
        // DWMWA_USE_IMMERSIVE_DARK_MODE = 20, BORDER_COLOR = 34,
        // CAPTION_COLOR = 35, TEXT_COLOR = 36.
        DwmSetWindowAttribute(hwnd, 20, &dark as *const _ as *const c_void, 4);
        DwmSetWindowAttribute(hwnd, 35, &colorref as *const _ as *const c_void, 4);
        DwmSetWindowAttribute(hwnd, 36, &text as *const _ as *const c_void, 4);
        DwmSetWindowAttribute(hwnd, 34, &colorref as *const _ as *const c_void, 4);
    }
    println!("{}", json!({ "caption": cleaned }));
    Ok(())
}

fn print_pdf(file: &str, printer: &str) -> Result<(), BoxErr> {
    let file_w = wide(file);
    let hwnd = app_window();
    let result = if printer.trim().is_empty() {
        let verb = wide("print");
        unsafe {
            ShellExecuteW(hwnd, verb.as_ptr(), file_w.as_ptr(), null(), null(), 0)
        }
    } else {
        let verb = wide("printto");
        let params = wide(&format!("\"{}\"", printer.replace('"', "")));
        unsafe {
            ShellExecuteW(
                hwnd,
                verb.as_ptr(),
                file_w.as_ptr(),
                params.as_ptr(),
                null(),
                0,
            )
        }
    };
    if result as isize <= 32 {
        return Err("Windows could not print that PDF".into());
    }
    println!("{}", json!({ "sent": true }));
    Ok(())
}

fn open_file(path: &str) -> Result<(), BoxErr> {
    let op = wide("open");
    let file = wide(path);
    let result = unsafe {
        ShellExecuteW(
            null_mut(),
            op.as_ptr(),
            file.as_ptr(),
            null(),
            null(),
            1,
        )
    };
    if result as isize <= 32 {
        return Err("Windows could not open that file".into());
    }
    println!("{}", json!({ "opened": true }));
    Ok(())
}
