# Heroku

The web process is `bin/start-heroku.sh`. It listens on `$PORT`, runs on CPU, and writes every finished image or video into `storage/output` on the dyno disk (`/app/storage/output`).

That directory is local to the running web dyno. It is not S3, and it is wiped when the dyno restarts or you deploy again. Download the file from the UI before that happens. A one-off `heroku run` dyno does not see those files.

## Deploy

```bash
heroku create your-app-name
heroku stack:set heroku-24 --app your-app-name
heroku buildpacks:add --index 1 heroku-community/apt --app your-app-name
heroku buildpacks:add heroku/python --app your-app-name
heroku git:remote -a your-app-name
git push heroku master
heroku ps:scale web=1:performance-m --app your-app-name
```

Use Performance-M or larger. Eco and Basic dynos do not have enough RAM. There is no GPU, so keep source clips short.

First boot downloads models into `.assets` while a placeholder holds the port. Refresh the app URL after a few minutes.
