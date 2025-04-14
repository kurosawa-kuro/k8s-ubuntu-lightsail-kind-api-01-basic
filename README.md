# k8s-ubuntu-lightsail-kind-api-01-basic

以下は **Ingress** を完全に使わず、サーバー内部（EC2 や Lightsail インスタンス上）でのみ動作確認を行う **最小構成**のサンプルです。NodePort も利用しないため、外部公開は行わず **ClusterIP** のみで内部疎通を確認します。

ディレクトリパスはご要望に合わせて `~/dev/k8s-ubuntu-lightsail-kind-api-01-basic` としています。  
コンテナイメージは `986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080:latest` を使用し、Express API はコンテナ内ポート `8080` で起動する想定です。

---

# 構成概要

1. **kind クラスタ作成（ECR プル対応）**  
2. **Deployment / Service (ClusterIP) 適用**  
3. **サーバ内部で動作確認**  

> - **Ingress** は不要・禁止  
> - **NodePort** も不要  
> - **サーバ内部でのみ API を curl する**

---

## 0️⃣ 前提

- OS: Ubuntu 22.04 (Lightsail や EC2 上を想定)
- ストレージ: 30GB 以上 (Docker, kind 用)
- すでにインストール済:
  - Docker
  - kind
  - kubectl
  - AWS CLI ( `aws configure`済 )
- ECR に `container-nodejs-api-8080:latest` が push 済み
  - リポジトリ: `986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080:latest`
- Express API が `PORT=8080` で起動、ヘルスチェックが `GET /` で確認できる想定

---

## 1️⃣ kind クラスタ作成（ECR プル対応）

```bash
cd ~/dev/k8s-ubuntu-lightsail-kind-api-01-basic

# ECR から Pull するためのトークンを取得
ECR_TOKEN=$(aws ecr get-login-password --region ap-northeast-1)

cat <<EOF > kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.auths."986154984217.dkr.ecr.ap-northeast-1.amazonaws.com"]
        username = "AWS"
        password = "$ECR_TOKEN"
EOF

# kind クラスタ作成
kind create cluster --config kind-cluster.yaml

# 作成されたクラスタ一覧を確認
kind get clusters
# => kind
```

> **メモ**: 今回は外部にポートを晒さないため、`extraPortMappings` は不要です。

---

## 2️⃣ Deployment / Service (ClusterIP) 定義 & 適用

`k8s` ディレクトリを作成して、その中にマニフェストをまとめます。

### ディレクトリ作成

```bash
mkdir -p ~/dev/k8s-ubuntu-lightsail-kind-api-01-basic/k8s
cd ~/dev/k8s-ubuntu-lightsail-kind-api-01-basic/k8s
```

### k8s/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: container-nodejs-api
  labels:
    app: container-nodejs-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: container-nodejs-api
  template:
    metadata:
      labels:
        app: container-nodejs-api
    spec:
      # ECR 認証に必要な Secret がある場合は指定
      # imagePullSecrets:
      # - name: regcred
      containers:
      - name: container-nodejs-api
        image: 986154984217.dkr.ecr.ap-northeast-1.amazonaws.com/container-nodejs-api-8080:latest
        imagePullPolicy: Always
        ports:
          - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
```

### k8s/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: container-nodejs-api
spec:
  selector:
    app: container-nodejs-api
  # ClusterIP のみ
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 8080    # Service 上のポート
      targetPort: 8080  # コンテナのポート
```

### 適用

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

---

## 3️⃣ サーバー内部で動作確認

外部公開しないので、同じサーバー上で `kubectl` を使って **Pod のログ確認** や **port-forward** を行い、API 応答を確認します。

### 3-1. Pod の起動・ログ確認

```bash
# Pod が Running になるまで待機
kubectl get pods -w

# Pod 名を確認
kubectl get pods
# => container-nodejs-api-xxxxxxxx

# ログを確認
kubectl logs -f deployment/container-nodejs-api
# => Express server running on port 8080
```

### 3-2. `port-forward` でローカルアクセス

ローカル(サーバー内部)でポートフォワードすると、`localhost:8080` でアクセスできます。

```bash
# Service を 8080 でフォワード
kubectl port-forward service/container-nodejs-api 8080:8080

# 別ターミナルまたは同ターミナルで別プロセスを起動し
curl -v http://localhost:8080/
# => {"health":"ok"} などアプリのレスポンスが得られる想定
```

### 3-3. Pod 内部から直接 curl

もしコンテナ内部からの動作を確認したい場合は、Pod に入って直接 `curl localhost:8080` でも OK です。  
ただし、`/bin/sh` などが備わっているイメージでない場合は利用できません。

```bash
# busybox 等のツールがある Pod があれば流用
# あるいは別途 test 用の Pod を立ち上げる
kubectl run testpod --image=busybox:stable --restart=Never -it -- /bin/sh

# (testpod 内で)
wget -qO- http://container-nodejs-api.default.svc.cluster.local:8080/
```

---

## 4️⃣ 片付け

テストが終わったら、kind クラスタを削除します。

```bash
kind delete cluster
kind get clusters
# => (何も表示されなければOK)
```

---

# まとめ

- **ディレクトリ**: `~/dev/k8s-ubuntu-lightsail-kind-api-01-basic`
- **利用リソース**
  - kind クラスタ (外部公開ポートなし)
  - **Deployment/Service(ClusterIP)** のみ
  - Ingress は使用しない
  - NodePort も使用しない
- **テスト方法**
  - `port-forward` でサーバー内部から `curl localhost:8080`
  - または Pod 内部からの直接アクセス
- **外部公開** は不要なので、ポート開放設定等は不要。

これで **Ingress 不要・禁止**、かつ **NodePort もなし** で **内部確認用** のみのシンプル構成が完成です。お役に立てば幸いです。