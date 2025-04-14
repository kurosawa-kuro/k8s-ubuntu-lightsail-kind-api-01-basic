# デフォルトのシェルをbashに設定
SHELL := /bin/bash

# アプリケーション設定
APP_NAME := container-nodejs-api-8080
APP_PORT := 8080
APP_VERSION ?= latest

# AWS/ECR設定
AWS_REGION ?= ap-northeast-1
AWS_ACCOUNT_ID ?= 986154984217
ECR_REGISTRY := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_REPOSITORY_NAME ?= $(APP_NAME)

# Docker イメージ設定
DOCKER_IMAGE := $(ECR_REPOSITORY_NAME):$(APP_VERSION)
DOCKER_ECR_IMAGE := $(ECR_REGISTRY)/$(DOCKER_IMAGE)

# 環境変数設定
export NODE_ENV ?= production
export PORT ?= $(APP_PORT)
export CURRENT_ENV ?= production
export CONFIG_MESSAGE ?= "本番環境用ConfigMapメッセージ"
export SECRET_KEY ?= "本番環境用シークレット"

# デフォルトターゲット
.PHONY: help \
	install clean \
	start test test-watch \
	docker-build docker-push \
	ecr-login check-aws-credentials \
	docker-local-build docker-local-run docker-local-stop \
	setup deploy status logs port-forward all

.DEFAULT_GOAL := help

# ------------------------
# ヘルプ
# ------------------------
help:
	@echo "📚 $(APP_NAME) アプリケーション - 利用可能なコマンド:"
	@echo ""
	@echo "🔧 開発環境セットアップ:"
	@echo "  make install      - 依存パッケージをインストール"
	@echo "  make clean        - node_modulesを削除"
	@echo ""
	@echo "🚀 アプリケーション実行:"
	@echo "  make start        - アプリケーションを起動"
	@echo "  make dev          - アプリケーションをデバッグモードで起動"
	@echo "  make test         - テストを実行"
	@echo "  make test-watch   - テストを監視モードで実行"
	@echo ""
	@echo "🐳 Docker操作:"
	@echo "  make docker-build - 本番用Dockerイメージをビルド"
	@echo "  make docker-push  - ECRにイメージをプッシュ"
	@echo "  make docker-local-build - ローカル用Dockerイメージをビルド"
	@echo "  make docker-local-run   - ローカルでDockerコンテナを実行"
	@echo "  make docker-local-stop  - ローカルのDockerコンテナを停止"
	@echo ""
	@echo "🔐 AWS/ECR操作:"
	@echo "  make ecr-login    - ECRにログイン"
	@echo "  make check-aws-credentials - AWS認証情報を確認"
	@echo ""
	@echo "🚀 Kubernetes操作:"
	@echo "  make setup      - kindクラスタのセットアップ"
	@echo "  make deploy     - Kubernetesリソースのデプロイ"
	@echo "  make status     - クラスタとリソースの状態確認"
	@echo "  make logs       - アプリケーションのログ表示"
	@echo "  make port-forward - ポートフォワード開始"
	@echo "  make all        - 完全なセットアップから動作確認まで実行"

# ------------------------
# 開発環境セットアップ
# ------------------------
install:
	@echo "📦 依存パッケージをインストールしています..."
	@npm ci
	@echo "✅ インストール完了"

clean:
	@echo "🧹 node_modulesを削除します..."
	@rm -rf node_modules
	@echo "✅ クリーンアップ完了"

# ------------------------
# アプリケーション実行
# ------------------------
dev:
	@echo "🚀 アプリケーションをデバッグモードで起動します - ポート: $(PORT)"
	@npm run dev

start:
	@echo "🚀 アプリケーションを起動します - ポート: $(PORT)"
	@npm start

test:
	@echo "🧪 テストを実行します..."
	@npm test

test-watch:
	@echo "👀 テストを監視モードで実行します..."
	@npm run test:watch

# ------------------------
# AWS/ECR操作
# ------------------------
check-aws-credentials:
	@echo "🔍 AWS認証情報を確認します..."
	@aws sts get-caller-identity || (echo "❌ AWS認証情報が無効です" && exit 1)
	@echo "✅ AWS認証情報が有効です"
	@echo "📝 現在の設定:"
	@echo "   - リージョン: $(AWS_REGION)"
	@echo "   - アカウントID: $(AWS_ACCOUNT_ID)"
	@echo "   - リポジトリ: $(ECR_REPOSITORY_NAME)"

ecr-login: check-aws-credentials
	@echo "🔐 ECRにログインします..."
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY) || (echo "❌ ECRログインに失敗しました" && exit 1)
	@echo "✅ ECRログイン完了"

# ------------------------
# Docker操作
# ------------------------
docker-build:
	@echo "🏗️  本番用Dockerイメージをビルドします..."
	@docker build -t $(DOCKER_IMAGE) .
	@docker tag $(DOCKER_IMAGE) $(DOCKER_ECR_IMAGE)
	@echo "✅ Dockerイメージのビルド完了"

docker-push: ecr-login
	@echo "⬆️  ECRにイメージをプッシュします..."
	@docker push $(DOCKER_ECR_IMAGE)
	@echo "✅ ECRプッシュ完了"

docker-local-build:
	@echo "🏗️  ローカル用Dockerイメージをビルドします..."
	@docker build -t $(APP_NAME)-local:$(APP_VERSION) .
	@echo "✅ ローカル用Dockerイメージのビルド完了"

docker-local-run:
	@echo "🚀 ローカルでDockerコンテナを実行します（Ctrl+Cで停止）..."
	@docker run \
		--name $(APP_NAME)-local \
		-p $(APP_PORT):$(APP_PORT) \
		-e NODE_ENV=development \
		-e PORT=$(APP_PORT) \
		-e CURRENT_ENV=development \
		-e CONFIG_MESSAGE="ローカル開発用ConfigMapメッセージ" \
		-e SECRET_KEY="ローカル開発用シークレット" \
		$(APP_NAME)-local:$(APP_VERSION)

docker-local-stop:
	@echo "🛑 ローカルで実行中のDockerコンテナを停止します..."
	@docker stop $(APP_NAME)-local || true
	@docker rm $(APP_NAME)-local || true
	@echo "✅ コンテナを停止しました"

# ------------------------
# Kubernetes操作
# ------------------------
setup:
	@echo "🚀 kindクラスタのセットアップを開始します..."
	$(eval ECR_TOKEN := $(shell aws ecr get-login-password --region $(AWS_REGION)))
	@echo "kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\nnodes:\n  - role: control-plane\ncontainerdConfigPatches:\n  - |-\n    [plugins.\"io.containerd.grpc.v1.cri\".registry]\n      [plugins.\"io.containerd.grpc.v1.cri\".registry.auths.\"$(ECR_REGISTRY)\"]\n        username = \"AWS\"\n        password = \"$(ECR_TOKEN)\"" > kind-cluster.yaml
	kind create cluster --config kind-cluster.yaml
	@echo "✅ kindクラスタのセットアップが完了しました"

deploy:
	@echo "📦 Kubernetesリソースをデプロイします..."
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/service.yaml
	@echo "✅ デプロイが完了しました"

status:
	@echo "📊 クラスタの状態を確認します..."
	@echo "\n>>> Podの状態:"
	kubectl get pods
	@echo "\n>>> Serviceの状態:"
	kubectl get services
	@echo "\n>>> Deploymentの状態:"
	kubectl get deployments

logs:
	@echo "📝 アプリケーションのログを表示します..."
	kubectl logs -f deployment/container-nodejs-api

port-forward:
	@echo "🔌 ポートフォワードを開始します (localhost:$(APP_PORT))..."
	kubectl port-forward service/container-nodejs-api $(APP_PORT):$(APP_PORT)

all: setup deploy
	@echo "⏳ Podの起動を待機中..."
	kubectl wait --for=condition=ready pod -l app=container-nodejs-api --timeout=60s
	@echo "✨ セットアップが完了しました。以下のコマンドで動作確認できます："
	@echo "  make status    - 状態確認"
	@echo "  make logs      - ログ確認"
	@echo "  make port-forward - ポートフォワード開始"
