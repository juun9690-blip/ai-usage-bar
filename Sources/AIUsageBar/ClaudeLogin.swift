import Foundation

/// Only a completion status crosses back to the app; credentials stay with Claude Code.
enum ClaudeLogin {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    static func script(executable: String, result: String) -> String {
        """
        #!/bin/bash
        umask 077
        finish() {
            code=$?
            trap - EXIT
            printf '%s' "$code" > \(quote(result))
        }
        trap finish EXIT
        trap 'exit 130' INT TERM HUP
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        printf '\nClaude 사용량 조회용 로그인입니다. 브라우저에서 로그인을 완료해 주세요.\n\n'
        \(quote(executable)) auth login
        code=$?
        if [ "$code" -eq 0 ]; then
            printf '\n로그인 완료. AI Usage에서 사용량을 다시 확인합니다. 이 창은 닫아도 됩니다.\n'
        else
            printf '\n로그인을 완료하지 못했습니다. AI Usage에서 다시 시도할 수 있습니다.\n'
        fi
        exit "$code"
        """
    }
}
