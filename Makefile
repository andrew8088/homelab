.PHONY: setup deploy clean status

setup:
	kubectl apply -f base/
	./scripts/create-secrets.sh

deploy:
	kubectl apply -R -f apps

clean:
	kubectl delete -f apps/ || true
	kubectl delete -f base/ || true

status:
	kubectl get pods,svc,pvc -n automation

logs:
	kubectl logs -f deployment/homeassistant -n automation
