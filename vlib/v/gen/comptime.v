// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module gen

import v.ast
import v.table
import v.util

fn (g &Gen) comptime_call(node ast.ComptimeCall) {
	if node.is_vweb {
		for stmt in node.vweb_tmpl.stmts {
			if stmt is ast.FnDecl {
				fn_decl := stmt as ast.FnDecl
				// insert stmts from vweb_tmpl fn
				if fn_decl.name.starts_with('main.vweb_tmpl') {
					g.inside_vweb_tmpl = true
					g.stmts(fn_decl.stmts)
					g.inside_vweb_tmpl = false
					break
				}
			}
		}
		g.writeln('vweb__Context_html(&app->vweb, _tmpl_res_$g.fn_decl.name); strings__Builder_free(&sb); string_free(&_tmpl_res_$g.fn_decl.name);')
		return
	}
	g.writeln('// $' + 'method call. sym="$node.sym.name"')
	mut j := 0
	result_type := g.table.find_type_idx('vweb.Result') // TODO not just vweb
	if node.method_name == 'method' {
		// `app.$method()`
		m := node.sym.find_method(g.comp_for_method) or {
			return
		}
		/*
		vals := m.attrs[0].split('/')
		args := vals.filter(it.starts_with(':')).map(it[1..])
		println(vals)
		for val in vals {
		}
		*/
		g.write('${util.no_dots(node.sym.name)}_${g.comp_for_method}(')
		g.expr(node.left)
		if m.args.len > 1 {
			g.write(', ')
		}
		for i in 0 .. m.args.len - 1 {
			g.write('((string*)${node.args_var}.data) [$i] ')
			if i < m.args.len - 2 {
				g.write(', ')
			}
		}
		g.write(' ); // vweb action call with args')
		return
	}
	for method in node.sym.methods {
		// if method.return_type != table.void_type {
		if method.return_type != result_type {
			continue
		}
		if method.args.len != 1 {
			continue
		}
		// receiver := method.args[0]
		// if !p.expr_var.ptr {
		// p.error('`$p.expr_var.name` needs to be a reference')
		// }
		amp := '' // if receiver.is_mut && !p.expr_var.ptr { '&' } else { '' }
		if j > 0 {
			g.write(' else ')
		}
		g.write('if (string_eq($node.method_name, tos_lit("$method.name"))) ')
		g.write('${util.no_dots(node.sym.name)}_${method.name}($amp ')
		g.expr(node.left)
		g.writeln(');')
		j++
	}
}

fn (mut g Gen) comp_if(it ast.CompIf) {
	ifdef := g.comp_if_to_ifdef(it.val, it.is_opt)
	if it.is_not {
		g.writeln('\n// \$if !$it.val {\n#ifndef ' + ifdef)
	} else {
		g.writeln('\n// \$if  $it.val {\n#ifdef ' + ifdef)
	}
	// NOTE: g.defer_ifdef is needed for defers called witin an ifdef
	// in v1 this code would be completely excluded
	g.defer_ifdef = if it.is_not { '\n#ifndef ' + ifdef } else { '\n#ifdef ' + ifdef }
	// println('comp if stmts $g.file.path:$it.pos.line_nr')
	g.stmts(it.stmts)
	g.defer_ifdef = ''
	if it.has_else {
		g.writeln('\n#else')
		g.defer_ifdef = if it.is_not { '\n#ifdef ' + ifdef } else { '\n#ifndef ' + ifdef }
		g.stmts(it.else_stmts)
		g.defer_ifdef = ''
	}
	g.writeln('\n#endif\n// } $it.val\n')
}

fn (mut g Gen) comp_for(node ast.CompFor) {
	g.writeln('// 2comptime $' + 'for {')
	sym := g.table.get_type_symbol(g.unwrap_generic(node.typ))
	vweb_result_type := table.new_type(g.table.find_type_idx('vweb.Result'))
	mut i := 0
	// g.writeln('string method = tos_lit("");')
	for method in sym.methods {
		// if method.attrs.len == 0 {
		// continue
		// }
		if method.return_type != vweb_result_type { // table.void_type {
			continue
		}
		g.comp_for_method = method.name
		g.writeln('\t// method $i')
		if i == 0 {
			g.write('\tstring ')
		}
		g.writeln('method = tos_lit("$method.name");')
		if i == 0 {
			g.write('\tstring ')
		}
		if method.attrs.len == 0 {
			g.writeln('attrs = tos_lit("");')
		} else {
			g.writeln('attrs = tos_lit("${method.attrs[0]}");')
		}
		g.stmts(node.stmts)
		i++
		g.writeln('')
	}
	g.writeln('// } comptime for')
}
