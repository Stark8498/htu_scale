ELEMENT.locale(ELEMENT.lang.en)
// Vue app

var app = new Vue({
  el: '#app',
  data: function() {
    return {
      table: [],
      windowHeight: 500,
      windowWidth: 900,
      lens: [
        {
          name: 'LenX',
          value: 'lenx'
        },
        {
          name: 'LenY',
          value: 'leny'
        },
        {
          name: 'LenZ',
          value: 'lenz'
        }
      ],
      active: false,
      selected_objects: 0
    }
  },
  methods: {
    changeMethod(){
      sketchup.changeMethod(this.method);
    },
    newRow(){
      const last = this.table[this.table.length - 1]

      var row = {}
      row.len = '';
      row.dim = "";

      if (last) row.len = last.len;


      this.table.push(row);
      setTimeout(() => {
        //  app.$refs['input_' + this.table.length - 1].focus();
      }, 300);
      console.log(this.table)
    },   
    removeRow(scope){
    //  console.log(scope)
     this.$delete(this.table, scope.$index)
    },  
    clearAll(){
      this.$confirm('Remove all dimensions. Continue?', 'Warning', {
        confirmButtonText: 'OK',
        cancelButtonText: 'Cancel',
        type: 'warning',
        center: true
      }).then(() => {
        this.table = [];
        sketchup.removeAll();
      }).catch(() => {
        // 
      });
    },  
    saveDims(){
      sketchup.saveDims(this.table);
    }, 
    setDim(dim){
      sketchup.setDim(dim);
    }, 
    refresh(){
      sketchup.refresh_dialog();
    },    
    exportDims(){
      sketchup.exportDims(this.table);
    },   
    loadDims(){
      sketchup.loadDims(this.method);
    },
    changeDim(dim){
      console.log(dim)
    },

    tableRowClassName({row, rowIndex}) {
      // return '';

      if (row.len == 'lenx') {
        return 'lenx'
      }
      else if (row.len == 'leny') {
        return 'leny'
      }
      else if (row.len == 'lenz') {
        return 'lenz'
      }
      else {
        return 'warning-row';
      }
    },
  },
  computed:{
  },
  mounted: function() {
    this.windowHeight = window.innerHeight;
    this.windowWidth = window.outerWidth;

    sketchup.ready(window.outerWidth, window.outerHeight);
    this.$nextTick(() => {
      window.addEventListener("resize", () => {
        app.windowHeight = window.innerHeight;
        app.windowWidth = window.outerWidth;
      });
    });

    // this.windowHeight += 1;
  },
})

function updateData(data) {
  app.table = data.table;
  app.windowHeight += 1
  setTimeout(() => {
    app.windowHeight -= 1
  }, 300);
}