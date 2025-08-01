<h2 class="bg-slate-400 p-4">AGREGAR NUEVO LOCAL</h2>
<form action="/api/venues/create" method="post">
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="name" class="mb-1">Nombre del Local</label>
        <input id="name" type="text" name="name" required class="p-2 border rounded" />
    
        <label for="address" class="mb-1">Dirección</label>
        <input id="address" type="text" name="address" required class="p-2 border rounded" />
    
        <label for="capacity" class="mb-1">Capacidad</label>
        <input id="capacity" type="number" name="capacity" required class="p-2 border rounded" />
    </div>
    
    <button type="submit">Crear Local</button>
</form>