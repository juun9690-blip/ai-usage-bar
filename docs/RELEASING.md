# 버전 업데이트와 배포

## 수정부터 사용자 설치까지

1. 기존 프로젝트에서 디자인·기능을 수정합니다. 필요하면 `codex/작업이름` 브랜치를 사용합니다.
2. 앱을 빌드하고 변경한 화면·동작을 확인합니다. 관련 테스트도 통과시킵니다.
3. 배포할 때 `VERSION`, `BUILD_NUMBER`, `CHANGELOG.md`와 README의 현재 버전을 함께 갱신합니다.
4. 변경 파일을 커밋하고 GitHub에 올립니다.
5. 해당 커밋에 `v버전` 태그를 붙이고 앱 ZIP을 GitHub Release에 업로드합니다.
6. 사용자는 새 ZIP으로 기존 앱을 교체합니다. 자동 업데이트는 아직 없습니다.

코드를 GitHub에 올리는 것만으로 이미 설치된 앱이 바뀌지는 않습니다. 작업 중인 수정은 여러 번 커밋하고, 배포할 준비가 됐을 때만 버전을 올려도 됩니다. 이미 공개한 태그·배포 파일을 덮어쓰지 말고, 새 버전을 만드세요.

## 버전 규칙

- 작은 디자인 조정·오류 수정: `0.3.0 → 0.3.1`
- 기능 추가: `0.3.1 → 0.4.0`
- `BUILD_NUMBER`: 배포마다 이전보다 큰 정수로 올립니다.

현재 버전은 `VERSION`, 빌드 번호는 `BUILD_NUMBER`에 있습니다. `Scripts/build.sh`가 두 값을 앱의 Info.plist에 반영합니다.

## 로컬 검증과 패키징

```sh
# 새 체크아웃에서 최초 1회 또는 커넥터 버전을 바꾼 뒤 실행
bash Scripts/fetch-connector.sh

swift test
bash Scripts/package-release.sh
```

`dist/AI-Usage-버전-macos-arm64.zip`과 `.sha256` 파일이 만들어집니다. 원본 서비스 계정이 연결된 Mac에서 사용량 조회와 변경한 UI를 별도로 확인하세요. 테스트는 모든 서비스의 실계정 연결을 보장하지 않습니다.

## GitHub 배포 예시

아래는 VERSION을 0.3.1로 변경하고 BUILD_NUMBER도 증가시킨 다음 실행하는 예시입니다. 먼저 `git status`와 `git diff`로 업로드 대상을 확인합니다.

```sh
git add Sources Tests Scripts Assets Package.swift README.md THIRD_PARTY_NOTICES.md VERSION BUILD_NUMBER CHANGELOG.md docs .gitignore
git commit -m 'Polish menu bar logos for 0.3.1'
git push origin main
git tag -a v0.3.1 -m 'AI Usage 0.3.1'
git push origin v0.3.1

gh release create v0.3.1 \
  dist/AI-Usage-0.3.1-macos-arm64.zip \
  dist/AI-Usage-0.3.1-macos-arm64.zip.sha256 \
  --verify-tag --prerelease \
  --title 'AI Usage 0.3.1 Preview' \
  --notes-file /path/to/release-notes.md
```

릴리스 노트 파일에는 해당 버전 변경 내용과 알려진 제한을 적습니다. 프리뷰 단계에서는 `--prerelease`를 유지합니다.

## 자동 업데이트를 붙이려면

별도 기능 작업으로 Sparkle 같은 macOS 업데이트 프레임워크를 앱에 연결해야 합니다. 업데이트 피드, 업데이트 서명 키, 배포 파일 검증과 재시작 흐름이 필요하며 GitHub Releases만 생성한다고 자동 설치가 되지는 않습니다.

- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Sparkle 문서](https://sparkle-project.org/documentation/)
- [Apple Developer ID 배포](https://developer.apple.com/developer-id/)

현재 빌드는 ad-hoc 서명입니다. 일반 배포용 Developer ID 서명·공증과 자동 업데이트 도입은 별도로 준비해야 합니다. 서명 키·인증 파일·로컬 백업은 저장소에 올리지 않습니다.
