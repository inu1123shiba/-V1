# オノマトペ早押し対戦 v8

GitHub Pages + Supabase だけで公開する構成です。Vercelは不要です。

## 構成
- フロント: GitHub Pages（HTML/CSS/JS）
- 認証: Supabase Anonymous Auth
- DB: Supabase Postgres
- リアルタイム: Supabase Realtime Broadcast / Presence
- サーバー側ゲーム判定: Supabase Database RPC

GitHub Pagesはリポジトリから静的HTML/CSS/JSを公開できます。Supabase Edge Functionsはサーバー処理向けですが、今回のゲーム判定はPostgres RPCで完結させています。

## 1. Supabaseプロジェクト
1. Supabaseでプロジェクトを作成。
2. Authentication > Providers で Anonymous Sign-ins を有効化。
3. SQL Editorで `supabase_schema.sql` を全文実行。
4. Settings > API から Project URL と Publishable Key を確認。

## 2. config.js
`config.js` の2か所を自分の値に置き換える。

```js
window.SUPABASE_URL = "https://YOUR_PROJECT_REF.supabase.co";
window.SUPABASE_PUBLISHABLE_KEY = "sb_publishable_...";
```

**service_role key / secret keyは絶対に入れない。**

## 3. GitHub
1. GitHubで新しいrepositoryを作る。
2. このフォルダの中身をrepositoryのルートへアップロード。
3. `config.js` もアップロード。
4. Settings > Pages > Source を GitHub Actions にする。
5. `main`へpushすると `.github/workflows/pages.yml` が公開する。

公開URLは通常 `https://ユーザー名.github.io/リポジトリ名/` です。

## 4. 友達と遊ぶ
1. 公開URLを開く。
2. 名前を入力して「ルームを作る」。
3. 共有ボタンまたはQRコードで参加URLを送る。
4. 2～4人がREADY。
5. ホストがゲーム開始。

## ゲーム仕様
- 最大4人
- 2人以上で開始
- 全員READY必須
- 10問
- 1問10秒
- 最初に押した1人が回答
- 正解 +100pt / 不正解 0pt / 時間切れ 0pt
- 回答後に👍/👎を1人1票
- 5秒後に次問題
- 10問終了後ランキング
- ホスト再戦
- ホスト退出時は次の参加者へ自動移行
- 途中参加不可

## 問題作成
トップの「問題を作る」から作成できます。
- オノマトペ2個
- ジャンル
- 正解
- 許容回答
- 難易度★1～★3
- 公開/非公開

公開問題が10問以上ないとゲーム開始できません。

## 注意
GitHub Pagesは静的ホスティングなので、Supabaseの秘密鍵を置く必要はありません。ブラウザに置くのはSupabaseのPublishable Keyだけにしてください。
