"use strict";

/* global fetch, sessionStorage, window, document, FormData */

(function () {
    const PRICE_RE = /^[0-9]+(\.[0-9]{1,2})?$/;
    const STORAGE_TOKEN = "inventario.token";
    const STORAGE_USER = "inventario.username";

    const state = {
        token: readSession(STORAGE_TOKEN),
        username: readSession(STORAGE_USER),
        products: [],
        requestId: 0,
        editingId: null,
    };

    const els = {
        authView: document.getElementById("auth-view"),
        workspace: document.getElementById("workspace"),
        sessionBox: document.getElementById("session-box"),
        sessionUser: document.getElementById("session-user"),
        logoutBtn: document.getElementById("logout-btn"),
        tabs: Array.from(document.querySelectorAll(".tab")),
        loginForm: document.getElementById("login-form"),
        registerForm: document.getElementById("register-form"),
        authStatus: document.getElementById("auth-status"),
        appStatus: document.getElementById("app-status"),
        inventorySummary: document.getElementById("inventory-summary"),
        productCount: document.getElementById("product-count"),
        productsBody: document.getElementById("products-body"),
        productsEmpty: document.getElementById("products-empty"),
        productForm: document.getElementById("product-form"),
        productFormTitle: document.getElementById("product-form-title"),
        productSubmit: document.getElementById("product-submit"),
        cancelEditBtn: document.getElementById("cancel-edit-btn"),
        refreshBtn: document.getElementById("refresh-btn"),
        reportBtn: document.getElementById("report-btn"),
    };

    class RpcError extends Error {
        constructor(error) {
            super(error.message || "Error RPC");
            this.name = "RpcError";
            this.code = error.code;
            this.data = error.data;
        }
    }

    /* --- Sesión --- */

    function readSession(key) {
        try {
            return sessionStorage.getItem(key) || "";
        } catch {
            return "";
        }
    }

    function writeSession(key, value) {
        try {
            if (value) {
                sessionStorage.setItem(key, value);
            } else {
                sessionStorage.removeItem(key);
            }
        } catch {
            /* sessionStorage puede estar bloqueado; la sesión vive en memoria. */
        }
    }

    function saveSession(result) {
        state.token = result.token;
        state.username = result.username;
        writeSession(STORAGE_TOKEN, state.token);
        writeSession(STORAGE_USER, state.username);
    }

    function clearSession() {
        state.token = "";
        state.username = "";
        state.products = [];
        state.editingId = null;
        writeSession(STORAGE_TOKEN, "");
        writeSession(STORAGE_USER, "");
    }

    /* --- RPC --- */

    async function rpc(method, params) {
        state.requestId += 1;
        const response = await fetch("/", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                jsonrpc: "2.0",
                id: state.requestId,
                method,
                params: params || {},
            }),
        });
        if (!response.ok) {
            throw new Error("No se pudo comunicar con el servidor (HTTP " + response.status + ").");
        }
        const payload = await response.json();
        if (payload.error) {
            throw new RpcError(payload.error);
        }
        return payload.result;
    }

    function privateParams(params) {
        return Object.assign({ token: state.token }, params || {});
    }

    /* --- UI helpers --- */

    function setStatus(element, message, kind) {
        element.textContent = message || "";
        element.className = "status" + (kind ? " is-" + kind : "");
    }

    function setBusy(form, busy) {
        form.setAttribute("aria-busy", busy ? "true" : "false");
        form.querySelectorAll("button").forEach(function (button) {
            button.disabled = busy;
        });
    }

    function messageFor(error) {
        if (!(error instanceof RpcError)) {
            return "No se pudo conectar con el servidor. Verificá que esté levantado.";
        }
        switch (error.code) {
            case -32700:
                return "El servidor no pudo interpretar la solicitud.";
            case -32600:
                return "Solicitud inválida.";
            case -32601:
                return "La operación solicitada no está disponible.";
            case -32602:
                return typeof error.data === "string" ? error.data : "Datos inválidos.";
            case -32603:
                return "Ocurrió un error interno. Revisá el archivo error.log.";
            case -32001:
                return "La sesión expiró. Volvé a ingresar.";
            case -32002:
                return "Usuario o contraseña incorrectos.";
            case -32003:
                return "El producto no existe o ya fue eliminado.";
            case -32004:
                return "Ese usuario ya está registrado.";
            case -32005:
                return "La operación no está permitida.";
            default:
                return error.message || "Error inesperado.";
        }
    }

    function handleAppError(error) {
        if (error instanceof RpcError && error.code === -32001) {
            clearSession();
            showAuth(messageFor(error));
            return;
        }
        setStatus(els.appStatus, messageFor(error), "error");
    }

    function showAuth(message) {
        els.workspace.hidden = true;
        els.authView.hidden = false;
        els.sessionBox.hidden = true;
        setStatus(els.authStatus, message || "", message ? "info" : "");
        const username = els.loginForm.querySelector('[name="username"]');
        if (username) {
            username.focus();
        }
    }

    async function enterWorkspace() {
        els.authView.hidden = true;
        els.workspace.hidden = false;
        els.sessionBox.hidden = false;
        els.sessionUser.textContent = state.username;
        resetProductForm();
        await loadProducts();
    }

    /* --- Productos --- */

    function formatPrice(price) {
        return "$ " + price;
    }

    function productCountLabel(count) {
        return count + (count === 1 ? " producto" : " productos");
    }

    function renderProducts() {
        els.productsBody.replaceChildren();
        els.productsEmpty.hidden = state.products.length !== 0;
        els.productCount.textContent = productCountLabel(state.products.length);
        els.inventorySummary.textContent =
            state.products.length === 0
                ? "Todavía no hay productos en el inventario."
                : productCountLabel(state.products.length) + " en inventario.";

        state.products.forEach(function (product) {
            const row = document.createElement("tr");

            const idCell = document.createElement("td");
            idCell.textContent = product.id;
            row.appendChild(idCell);

            const nameCell = document.createElement("td");
            nameCell.textContent = product.nombre;
            row.appendChild(nameCell);

            const priceCell = document.createElement("td");
            priceCell.className = "num";
            priceCell.textContent = formatPrice(product.precio);
            row.appendChild(priceCell);

            const actionsCell = document.createElement("td");
            actionsCell.className = "actions-col";
            const actions = document.createElement("div");
            actions.className = "row-actions";

            const editButton = document.createElement("button");
            editButton.type = "button";
            editButton.className = "btn btn-ghost btn-small";
            editButton.textContent = "Editar";
            editButton.addEventListener("click", function () {
                startEdit(product);
            });

            const deleteButton = document.createElement("button");
            deleteButton.type = "button";
            deleteButton.className = "btn btn-danger btn-small";
            deleteButton.textContent = "Eliminar";
            deleteButton.addEventListener("click", function () {
                deleteProduct(product);
            });

            actions.append(editButton, deleteButton);
            actionsCell.appendChild(actions);
            row.appendChild(actionsCell);
            els.productsBody.appendChild(row);
        });
    }

    async function loadProducts(options) {
        const settings = options || {};
        if (settings.clearStatus !== false) {
            setStatus(els.appStatus, "", "");
        }
        els.inventorySummary.textContent = "Cargando inventario…";
        try {
            const result = await rpc("products.list", privateParams());
            state.products = Array.isArray(result.products) ? result.products : [];
            renderProducts();
            return true;
        } catch (error) {
            state.products = [];
            renderProducts();
            handleAppError(error);
            return false;
        }
    }

    function resetProductForm() {
        state.editingId = null;
        els.productForm.reset();
        els.productForm.elements.id.value = "";
        els.productFormTitle.textContent = "Nuevo producto";
        els.productSubmit.textContent = "Agregar";
        els.cancelEditBtn.hidden = true;
    }

    function startEdit(product) {
        state.editingId = product.id;
        els.productForm.elements.id.value = product.id;
        els.productForm.elements.nombre.value = product.nombre;
        els.productForm.elements.precio.value = product.precio;
        els.productFormTitle.textContent = "Editar producto";
        els.productSubmit.textContent = "Guardar cambios";
        els.cancelEditBtn.hidden = false;
        setStatus(els.appStatus, "Editando el producto ID " + product.id + ".", "info");
        els.productForm.elements.nombre.focus();
    }

    async function deleteProduct(product) {
        const confirmed = window.confirm(
            '¿Eliminar el producto "' + product.nombre + '" (ID ' + product.id + ")?"
        );
        if (!confirmed) {
            return;
        }
        try {
            await rpc("products.remove", privateParams({ id: product.id }));
            if (state.editingId === product.id) {
                resetProductForm();
            }
            const loaded = await loadProducts({ clearStatus: false });
            if (loaded) {
                setStatus(els.appStatus, "Producto eliminado.", "success");
            }
        } catch (error) {
            handleAppError(error);
            if (error instanceof RpcError && error.code === -32003) {
                await loadProducts({ clearStatus: false });
            }
        }
    }

    async function submitProduct(event) {
        event.preventDefault();
        const form = els.productForm;
        const id = state.editingId;
        const nombre = form.elements.nombre.value.trim();
        const precio = form.elements.precio.value.trim();

        if (!nombre) {
            setStatus(els.appStatus, "Ingresá un nombre para el producto.", "error");
            form.elements.nombre.focus();
            return;
        }
        if (!PRICE_RE.test(precio)) {
            setStatus(els.appStatus, "El precio debe ser un entero o tener hasta dos decimales.", "error");
            form.elements.precio.focus();
            return;
        }

        setBusy(form, true);
        setStatus(els.appStatus, "", "");
        try {
            let message;
            if (id === null) {
                await rpc("products.add", privateParams({ nombre: nombre, precio: precio }));
                message = "Producto agregado.";
            } else {
                await rpc("products.update", privateParams({ id: id, nombre: nombre, precio: precio }));
                message = "Producto actualizado.";
            }
            resetProductForm();
            const loaded = await loadProducts({ clearStatus: false });
            if (loaded) {
                setStatus(els.appStatus, message, "success");
            }
        } catch (error) {
            handleAppError(error);
        } finally {
            setBusy(form, false);
        }
    }

    /* --- Autenticación --- */

    function selectTab(name) {
        els.tabs.forEach(function (tab) {
            const active = tab.dataset.tab === name;
            tab.classList.toggle("is-active", active);
            tab.setAttribute("aria-selected", active ? "true" : "false");
        });
        els.loginForm.hidden = name !== "login";
        els.registerForm.hidden = name !== "register";
        setStatus(els.authStatus, "", "");
        const form = name === "login" ? els.loginForm : els.registerForm;
        const username = form.querySelector('[name="username"]');
        if (username) {
            username.focus();
        }
    }

    async function submitLogin(event) {
        event.preventDefault();
        const form = els.loginForm;
        const username = form.elements.username.value.trim();
        const password = form.elements.password.value;

        setStatus(els.authStatus, "", "");
        setBusy(form, true);
        try {
            const result = await rpc("auth.login", { username: username, password: password });
            saveSession(result);
            form.reset();
            await enterWorkspace();
        } catch (error) {
            setStatus(els.authStatus, messageFor(error), "error");
        } finally {
            setBusy(form, false);
        }
    }

    async function submitRegister(event) {
        event.preventDefault();
        const form = els.registerForm;
        const username = form.elements.username.value.trim();
        const password = form.elements.password.value;
        const password2 = form.elements.password2.value;

        if (password !== password2) {
            setStatus(els.authStatus, "Las contraseñas no coinciden.", "error");
            form.elements.password2.focus();
            return;
        }

        setStatus(els.authStatus, "", "");
        setBusy(form, true);
        try {
            await rpc("auth.register", { username: username, password: password });
            const result = await rpc("auth.login", { username: username, password: password });
            saveSession(result);
            form.reset();
            await enterWorkspace();
        } catch (error) {
            setStatus(els.authStatus, messageFor(error), "error");
        } finally {
            setBusy(form, false);
        }
    }

    async function logout() {
        els.logoutBtn.disabled = true;
        try {
            if (state.token) {
                await rpc("auth.logout", privateParams());
            }
        } catch {
            /* El logout local siempre procede, aunque el token ya haya vencido. */
        } finally {
            els.logoutBtn.disabled = false;
            clearSession();
            showAuth("Sesión cerrada.");
        }
    }

    /* --- Reporte --- */

    async function generateReport() {
        const reportWindow = window.open("about:blank", "_blank");
        if (reportWindow) {
            reportWindow.document.title = "Generando reporte…";
            reportWindow.document.body.textContent = "Generando reporte…";
        }
        els.reportBtn.disabled = true;
        setStatus(els.appStatus, "Generando reporte…", "info");
        try {
            const result = await rpc("report.generate", privateParams());
            setStatus(els.appStatus, "Reporte generado en " + result.path + ".", "success");
            if (reportWindow) {
                reportWindow.opener = null;
                reportWindow.location.href = result.url;
            } else {
                setStatus(
                    els.appStatus,
                    "Reporte generado. El navegador bloqueó la pestaña: abrí " + result.url + ".",
                    "info"
                );
            }
        } catch (error) {
            if (reportWindow) {
                reportWindow.close();
            }
            handleAppError(error);
        } finally {
            els.reportBtn.disabled = false;
        }
    }

    /* --- Wiring --- */

    els.tabs.forEach(function (tab) {
        tab.addEventListener("click", function () {
            selectTab(tab.dataset.tab);
        });
    });

    els.loginForm.addEventListener("submit", submitLogin);
    els.registerForm.addEventListener("submit", submitRegister);
    els.productForm.addEventListener("submit", submitProduct);
    els.cancelEditBtn.addEventListener("click", function () {
        resetProductForm();
        setStatus(els.appStatus, "", "");
    });
    els.logoutBtn.addEventListener("click", logout);
    els.reportBtn.addEventListener("click", generateReport);
    els.refreshBtn.addEventListener("click", async function () {
        els.refreshBtn.disabled = true;
        try {
            const loaded = await loadProducts({ clearStatus: false });
            if (loaded) {
                setStatus(els.appStatus, "Inventario actualizado.", "info");
            }
        } finally {
            els.refreshBtn.disabled = false;
        }
    });

    if (state.token) {
        enterWorkspace().catch(function () {
            clearSession();
            showAuth("La sesión expiró. Volvé a ingresar.");
        });
    } else {
        showAuth("");
    }
})();
