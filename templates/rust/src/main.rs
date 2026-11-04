use std::time::{SystemTime, UNIX_EPOCH};

use tiny_http::{Response, Server};

fn main() {
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let server = Server::http(("0.0.0.0", port)).expect("failed to bind");
    println!("kit-sample-rs listening on :{port}");
    for request in server.incoming_requests() {
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let body = format!("{{\"ok\":true,\"stack\":\"rust\",\"epoch\":{secs}}}\n");
        let content_type: tiny_http::Header = "Content-Type: application/json"
            .parse()
            .expect("valid header");
        let _ = request.respond(Response::from_string(body).with_header(content_type));
    }
}
