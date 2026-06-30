import Foundation

if CommandLine.arguments.contains("--diagnose") {
    CookieDiagnostics.printReport()
    exit(0)
}

switch CookieReader.findToken() {
case .success(let token):
    print(token)
case .failure(let error):
    CookieDiagnostics.printReport()
    fputs("\(error.description)\n", stderr)
    exit(error.exitCode)
}
