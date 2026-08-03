# Health check test case
def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

# POST req test case
def test_create_monitor(client):
    response = client.post(
        "/monitors",
        json={"name": "test site", "url": "https://example.com"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "test site"
    assert body["url"] == "https://example.com/"
    assert body["status"] == "unknown"
    assert body["id"] is not None

# GET Req test case
def test_get_monitor(client):
    created = client.post(
        "/monitors",
        json={"name": "test site", "url": "https://example.com"},
    ).json()

    response = client.get(f"/monitors/{created['id']}")
    assert response.status_code == 200
    assert response.json()["name"] == "test site"

# Test case for 404 path (NOT FOUND)
def test_get_monitor_not_found(client):
    response = client.get("/monitors/999")
    assert response.status_code == 404

# Test case to list all added elements
def test_list_monitors(client):
    client.post("/monitors", json={"name": "site one", "url": "https://example.com"})
    client.post("/monitors", json={"name": "site two", "url": "https://example.org"})

    response = client.get("/monitors")
    assert response.status_code == 200
    assert len(response.json()) == 2

# Test case for PATCH method
def test_update_monitor(client):
    created = client.post(
        "/monitors",
        json={"name": "test site", "url": "https://example.com"},
    ).json()

    response = client.patch(f"/monitors/{created['id']}", json={"name": "renamed site"})
    assert response.status_code == 200
    assert response.json()["name"] == "renamed site"
    assert response.json()["url"] == "https://example.com/"

# Test case for checking we can't PATCH a non-existing entry
def test_update_monitor_not_found(client):
    response = client.patch("/monitors/999", json={"name": "renamed site"})
    assert response.status_code == 404

# Test case to delete entry and validate
def test_delete_monitor(client):
    created = client.post(
        "/monitors",
        json={"name": "test site", "url": "https://example.com"},
    ).json()

    response = client.delete(f"/monitors/{created['id']}")
    assert response.status_code == 204

    response = client.get(f"/monitors/{created['id']}")
    assert response.status_code == 404

# Ensures we can't delete that was never created
def test_delete_monitor_not_found(client):
    response = client.delete("/monitors/999")
    assert response.status_code == 404

# Checks whether Pydantic validation actually rejects for a missing required URL field
def test_create_monitor_missing_url(client):
    response = client.post("/monitors", json={"name": "test site"})
    assert response.status_code == 422
