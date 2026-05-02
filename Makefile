CLUSTER_NAME := security-dojo
NAMESPACE    := dojo
IMAGE_NAME   := security-dojo-app
IMAGE_TAG    := vulnerable

.PHONY: all apply-vulnerable-env build load-image create-cluster deploy clean

all: apply-vulnerable-env

apply-vulnerable-env: create-cluster build load-image deploy
	@echo "------------------------------------------------------------"
	@echo "✅  脆弱な環境のデプロイが完了しました"
	@echo "  kubectl get pods -A  でPodの状態を確認してください"
	@echo "  http://localhost:8080 でアプリにアクセスできます"
	@echo "------------------------------------------------------------"

create-cluster:
	@echo "==> Kindクラスタを作成中..."
	@if kind get clusters | grep -q $(CLUSTER_NAME); then \
		echo "  クラスタ '$(CLUSTER_NAME)' は既に存在します。スキップします。"; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml; \
	fi
	kubectl config use-context kind-$(CLUSTER_NAME)

build:
	@echo "==> Dockerイメージをビルド中: $(IMAGE_NAME):$(IMAGE_TAG)"
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) ./app

load-image:
	@echo "==> イメージをKindクラスタにロード中..."
	kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(CLUSTER_NAME)

deploy:
	@echo "==> Namespaceを作成中..."
	kubectl apply -f k8s/base/namespace.yaml
	@echo "==> 脆弱なK8sリソースをapply中..."
	kubectl apply -k k8s/overlays/dev

clean:
	@echo "==> Kindクラスタを削除中..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "✅  クリーンアップ完了"

check-tools:
	@echo "==> 必要なツールの確認..."
	@docker --version
	@kubectl version --client --short 2>/dev/null || kubectl version --client
	@kind version
	@terraform version -json | python3 -c "import sys,json; d=json.load(sys.stdin); print('Terraform', d['terraform_version'])"
